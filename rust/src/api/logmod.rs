use crate::api::logger;

use crate::frb_generated::StreamSink;

#[flutter_rust_bridge::frb]
pub struct LogEntry {
    pub time_millis: i64,
    pub level: i32,
    pub tag: String,
    pub msg: String,
}

#[flutter_rust_bridge::frb]
pub fn create_log_stream(s: StreamSink<LogEntry>) {
    logger::SendToDartLogger::set_stream_sink(s);
}

#[flutter_rust_bridge::frb]
pub fn rust_set_up() {
    logger::init_logger();
}
