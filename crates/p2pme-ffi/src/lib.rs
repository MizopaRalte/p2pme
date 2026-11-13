use p2pme_core::ticket::{AccessMode, PairingTicket, SyncMode};
use p2pme_core::P2PNode;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;

pub struct P2PContext {
    pub rt: Runtime,
    pub node: Arc<P2PNode>,
    pub watchers: Mutex<HashMap<String, p2pme_core::storage::FolderWatcher>>,
}

#[no_mangle]
pub extern "C" fn p2pme_init(db_dir: *const c_char, port: u16) -> *mut P2PContext {
    if db_dir.is_null() {
        return std::ptr::null_mut();
    }
    let c_str = unsafe { CStr::from_ptr(db_dir) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let rt = match Runtime::new() {
        Ok(r) => r,
        Err(_) => return std::ptr::null_mut(),
    };

    let node_res = rt.block_on(async { P2PNode::new(path_str, port).await });

    match node_res {
        Ok(node) => Box::into_raw(Box::new(P2PContext {
            rt,
            node: Arc::new(node),
            watchers: Mutex::new(HashMap::new()),
        })),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn p2pme_get_node_id(ctx: *mut P2PContext) -> *mut c_char {
    if ctx.is_null() {
        return std::ptr::null_mut();
    }
    let ctx = unsafe { &*ctx };
    CString::new(ctx.node.node_id.clone())
        .map(|c| c.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn p2pme_get_port(ctx: *mut P2PContext) -> u16 {
    if ctx.is_null() {
        return 0;
    }
    let ctx = unsafe { &*ctx };
    ctx.node.transport.listening_port
}

#[no_mangle]
pub extern "C" fn p2pme_share_folder(
    ctx: *mut P2PContext,
    folder_path: *const c_char,
    folder_name: *const c_char,
    is_ro: bool,
    sync_mode: u8, // 0 = TwoWay, 1 = CameraBackup, 2 = Archive
) -> *mut c_char {
    if ctx.is_null() || folder_path.is_null() || folder_name.is_null() {
        return std::ptr::null_mut();
    }
    let ctx = unsafe { &*ctx };
    let path_str = unsafe { CStr::from_ptr(folder_path).to_str().unwrap_or("") };
    let name_str = unsafe { CStr::from_ptr(folder_name).to_str().unwrap_or("") };
    let access = if is_ro {
        AccessMode::ReadOnly
    } else {
        AccessMode::ReadWrite
    };
    let mode = match sync_mode {
        1 => SyncMode::CameraBackup,
        2 => SyncMode::Archive,
        _ => SyncMode::TwoWay,
    };
    let token = format!(
        "tok_{}",
        &blake3::hash(&rand::random::<[u8; 16]>()).to_hex()[..12]
    );

    let res: anyhow::Result<String> = ctx.rt.block_on(async {
        let ticket = ctx
            .node
            .share_folder(path_str, name_str, access, mode, &token)
            .await?;
        let payload = ticket.to_string_payload()?;
        Ok(payload)
    });

    match res {
        Ok(payload) => CString::new(payload)
            .map(|c| c.into_raw())
            .unwrap_or(std::ptr::null_mut()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn p2pme_sync_ticket(
    ctx: *mut P2PContext,
    ticket_str: *const c_char,
    destination: *const c_char,
) -> i32 {
    if ctx.is_null() || ticket_str.is_null() || destination.is_null() {
        return -1;
    }
    let ctx = unsafe { &*ctx };
    let ticket_str = unsafe { CStr::from_ptr(ticket_str).to_str().unwrap_or("") };
    let dest_str = unsafe { CStr::from_ptr(destination).to_str().unwrap_or("") };

    let parsed_ticket = match PairingTicket::from_string_payload(ticket_str) {
        Ok(t) => t,
        Err(_) => return -2,
    };

    let res = ctx
        .rt
        .block_on(async { ctx.node.sync_folder(dest_str, &parsed_ticket).await });

    match res {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

#[no_mangle]
pub extern "C" fn p2pme_create_drop(
    ctx: *mut P2PContext,
    files_json: *const c_char,
) -> *mut c_char {
    if ctx.is_null() || files_json.is_null() {
        return std::ptr::null_mut();
    }
    let ctx = unsafe { &*ctx };
    let json_str = unsafe { CStr::from_ptr(files_json).to_str().unwrap_or("[]") };

    let paths: Vec<String> = match serde_json::from_str(json_str) {
        Ok(p) => p,
        Err(_) => return std::ptr::null_mut(),
    };

    let path_bufs: Vec<std::path::PathBuf> = paths.into_iter().map(std::path::PathBuf::from).collect();

    let res = ctx.rt.block_on(async {
        let ticket = ctx.node.create_drop(path_bufs).await?;
        let payload = ticket.to_string_payload()?;
        let total_bytes: u64 = ticket.files.iter().map(|f| f.size).sum();

        let resp_json = serde_json::json!({
            "success": true,
            "drop_id": ticket.drop_id,
            "pin_code": ticket.pin_code,
            "ticket_payload": payload,
            "file_count": ticket.files.len(),
            "total_bytes": total_bytes,
        });

        Ok::<String, anyhow::Error>(resp_json.to_string())
    });

    match res {
        Ok(s) => CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut()),
        Err(e) => {
            let err_json = serde_json::json!({
                "success": false,
                "error": e.to_string()
            });
            CString::new(err_json.to_string()).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
        }
    }
}

#[no_mangle]
pub extern "C" fn p2pme_receive_drop(
    ctx: *mut P2PContext,
    ticket_payload: *const c_char,
    pin_code: *const c_char,
    destination: *const c_char,
) -> *mut c_char {
    if ctx.is_null() || destination.is_null() {
        return std::ptr::null_mut();
    }
    let ctx = unsafe { &*ctx };
    let payload_str = if ticket_payload.is_null() {
        ""
    } else {
        unsafe { CStr::from_ptr(ticket_payload).to_str().unwrap_or("") }
    };
    let pin_str = if pin_code.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(pin_code).to_str().ok() }
    };
    let dest_str = unsafe { CStr::from_ptr(destination).to_str().unwrap_or("") };

    let res = ctx.rt.block_on(async {
        if !payload_str.trim().is_empty() {
            let ticket = p2pme_core::DropTicket::from_string_payload(payload_str)?;
            let stats = ctx.node.receive_drop(&ticket, pin_str, dest_str).await?;
            let resp_json = serde_json::json!({
                "success": true,
                "files_transferred": stats.files_transferred,
                "bytes_transferred": stats.bytes_transferred,
            });
            Ok::<String, anyhow::Error>(resp_json.to_string())
        } else if let Some(pin) = pin_str {
            let stats = ctx.node.receive_drop_by_pin(pin, dest_str).await?;
            let resp_json = serde_json::json!({
                "success": true,
                "files_transferred": stats.files_transferred,
                "bytes_transferred": stats.bytes_transferred,
            });
            Ok::<String, anyhow::Error>(resp_json.to_string())
        } else {
            anyhow::bail!("Either a Drop Ticket or 6-digit PIN must be provided");
        }
    });

    match res {
        Ok(s) => CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut()),
        Err(e) => {
            let err_json = serde_json::json!({
                "success": false,
                "error": e.to_string()
            });
            CString::new(err_json.to_string()).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
        }
    }
}

#[no_mangle]
pub extern "C" fn p2pme_start_watcher(
    ctx: *mut P2PContext,
    folder_path: *const c_char,
    folder_id: *const c_char,
) -> i32 {
    if ctx.is_null() || folder_path.is_null() || folder_id.is_null() {
        return -1;
    }
    let ctx = unsafe { &*ctx };
    let path_str = unsafe { CStr::from_ptr(folder_path).to_str().unwrap_or("") };
    let id_str = unsafe { CStr::from_ptr(folder_id).to_str().unwrap_or("") };

    let db_dir = ctx.node.db_dir.clone();
    let folder_id_string = id_str.to_string();
    let path_string = path_str.to_string();

    let watcher_res = p2pme_core::storage::FolderWatcher::watch(path_string.clone(), move || {
        let db_file = db_dir.join(format!("{}.db", &folder_id_string));
        if let Ok(mut cat) = p2pme_core::storage::StateCatalog::new(&db_file) {
            cat.scan_directory(&folder_id_string, &path_string).ok();
        }
    });

    match watcher_res {
        Ok(w) => {
            let mut watchers = ctx.watchers.lock().unwrap();
            watchers.insert(id_str.to_string(), w);
            0
        }
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn p2pme_stop_watcher(ctx: *mut P2PContext, folder_id: *const c_char) -> i32 {
    if ctx.is_null() || folder_id.is_null() {
        return -1;
    }
    let ctx = unsafe { &*ctx };
    let id_str = unsafe { CStr::from_ptr(folder_id).to_str().unwrap_or("") };

    let mut watchers = ctx.watchers.lock().unwrap();
    if watchers.remove(id_str).is_some() {
        0
    } else {
        -2
    }
}

#[no_mangle]
pub extern "C" fn p2pme_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

#[no_mangle]
pub extern "C" fn p2pme_destroy(ctx: *mut P2PContext) {
    if !ctx.is_null() {
        unsafe { drop(Box::from_raw(ctx)) };
    }
}
