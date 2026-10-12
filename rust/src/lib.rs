//! ANT BLE protocol core. Based on maibms protocol documentation; see NOTICE.md.
use serde::Serialize;
use std::ffi::{c_char, CString};

pub fn crc16(bytes: &[u8]) -> u16 {
    let mut crc = 0xffffu16;
    for byte in bytes {
        crc ^= *byte as u16;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xa001
            } else {
                crc >> 1
            };
        }
    }
    crc
}
fn reg_bytes(fc: u8, reg: u16) -> [u8; 2] {
    if matches!(fc, 0x57 | 0x59 | 0x70 | 0x80) {
        reg.to_be_bytes()
    } else {
        reg.to_le_bytes()
    }
}
pub fn build(addr: u8, fc: u8, reg: u16, read_len: u8, data: &[u8]) -> Result<Vec<u8>, String> {
    if data.len() > 255 || (fc < 0x10 && !data.is_empty()) {
        return Err("invalid frame payload".into());
    }
    let mut frame = vec![0x7e, addr, fc];
    frame.extend(reg_bytes(fc, reg));
    frame.push(if fc < 0x10 {
        read_len
    } else {
        data.len() as u8
    });
    frame.extend(data);
    frame.extend(crc16(&frame[1..]).to_le_bytes());
    frame.extend([0xaa, 0x55]);
    Ok(frame)
}
pub fn read_realtime(addr: u8) -> Vec<u8> {
    build(addr, 1, 0, 245, &[]).unwrap()
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Segment {
    pub address: u8,
    pub function: u8,
    pub register: u16,
    pub length: u8,
    pub data: Vec<u8>,
    pub continuation: bool,
}
/// Segments are delivered only after the shared AA55 trailer. Max buffered packet 4096 bytes.
#[derive(Default)]
pub struct Parser {
    buf: Vec<u8>,
    pending: Vec<Segment>,
    pub discarded: u64,
}
impl Parser {
    pub fn reset(&mut self) {
        self.buf.clear();
        self.pending.clear();
    }
    pub fn buffered(&self) -> usize {
        self.buf.len()
    }
    pub fn feed(&mut self, bytes: &[u8]) -> Vec<Segment> {
        let mut result = vec![];
        for byte in bytes {
            self.buf.push(*byte);
            if self.buf.len() > 4096 {
                self.reset();
                self.discarded += 1;
                continue;
            }
            loop {
                if self.buf.is_empty() {
                    break;
                }
                let continuation = !self.pending.is_empty() && self.buf[0] != 0x7e;
                if continuation && self.buf[0] == 0xaa {
                    if self.buf.len() < 2 {
                        break;
                    }
                    if self.buf[1] == 0x55 {
                        self.buf.drain(..2);
                        result.append(&mut self.pending);
                        continue;
                    }
                }
                if !continuation && self.buf[0] != 0x7e {
                    self.buf.remove(0);
                    self.discarded += 1;
                    continue;
                }
                if !continuation && !self.pending.is_empty() {
                    self.pending.clear();
                }
                let header = if continuation { 4 } else { 6 };
                if self.buf.len() < header {
                    break;
                }
                let fc = self.buf[if continuation { 0 } else { 2 }];
                let length = self.buf[header - 1];
                let data_len = if !continuation && fc < 0x10 {
                    0
                } else {
                    length as usize
                };
                let size = header + data_len + 2;
                if self.buf.len() < size {
                    break;
                }
                let start = if continuation { 0 } else { 1 };
                let expected = u16::from_le_bytes([self.buf[size - 2], self.buf[size - 1]]);
                if crc16(&self.buf[start..size - 2]) != expected || self.pending.len() >= 16 {
                    self.buf.remove(0);
                    self.pending.clear();
                    self.discarded += 1;
                    continue;
                }
                let r = if continuation { 1 } else { 3 };
                let reg_pair = [self.buf[r], self.buf[r + 1]];
                let register = if matches!(fc, 0x57 | 0x59 | 0x70 | 0x80) {
                    u16::from_be_bytes(reg_pair)
                } else {
                    u16::from_le_bytes(reg_pair)
                };
                let address = if continuation {
                    self.pending[0].address
                } else {
                    self.buf[1]
                };
                self.pending.push(Segment {
                    address,
                    function: fc,
                    register,
                    length,
                    data: self.buf[header..header + data_len].to_vec(),
                    continuation,
                });
                self.buf.drain(..size);
            }
        }
        result
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Cell {
    pub voltage_v: f64,
    pub flags: u8,
}
#[derive(Debug, Clone, Serialize)]
pub struct Snapshot {
    pub permission: u8,
    pub state: u8,
    pub cells: Vec<Cell>,
    pub temperatures_c: Vec<i16>,
    pub protection_bits: String,
    pub warning_bits: String,
    pub mos_temperature_c: i16,
    pub balance_temperature_c: i16,
    pub voltage_v: f64,
    pub current_a: f64,
    pub soc: u16,
    pub soh: u16,
    pub discharge_mos: u8,
    pub charge_mos: u8,
    pub balance_state: u8,
    pub bms_type: u8,
    pub capacity_ah: f64,
    pub remaining_ah: f64,
    pub cycle_ah: f64,
    pub power_w: i32,
    pub runtime_s: u32,
    pub total_discharge_ah: f64,
    pub total_charge_ah: f64,
    pub total_discharge_s: Option<u32>,
    pub total_charge_s: Option<u32>,
    pub balance_raw: u32,
    pub max_cell_v: f64,
    pub max_cell_index: u16,
    pub min_cell_v: f64,
    pub min_cell_index: u16,
    pub delta_v: f64,
    pub average_v: f64,
    pub battery_type: u16,
    pub charge_time_s: Option<u32>,
    pub last_charge_gap_s: Option<u32>,
    pub high_speed_current_a: Option<f64>,
    pub charger_voltage_v: Option<f64>,
    pub charger_current_a: Option<f64>,
    pub charger_connected: Option<bool>,
    pub charge_remaining_min: Option<u16>,
    pub discharge_remaining_min: Option<u16>,
}
pub fn decode(data: &[u8]) -> Result<Snapshot, String> {
    if data.len() < 28 {
        return Err("realtime header truncated".into());
    }
    let n = data[3] as usize;
    let m = data[2] as usize;
    let t = 28 + 2 * n + 2 * m;
    if n == 0 || data.len() < t + 70 {
        return Err(format!(
            "invalid cell count or truncated core: need {}, got {}",
            t + 70,
            data.len()
        ));
    }
    let u16at = |i: usize| u16::from_le_bytes([data[i], data[i + 1]]);
    let s16at = |i: usize| i16::from_le_bytes([data[i], data[i + 1]]);
    let u32at = |i: usize| u32::from_le_bytes(data[i..i + 4].try_into().unwrap());
    let u64at = |i: usize| u64::from_le_bytes(data[i..i + 8].try_into().unwrap());
    let opt32 = |i: usize| {
        if data.len() >= i + 4 {
            Some(u32at(i))
        } else {
            None
        }
    };
    let opt16 = |i: usize| {
        if data.len() >= i + 2 {
            Some(u16at(i))
        } else {
            None
        }
    };
    Ok(Snapshot {
        permission: data[0],
        state: data[1],
        cells: (0..n)
            .map(|i| {
                let v = u16at(28 + 2 * i);
                Cell {
                    voltage_v: (v & 0x1fff) as f64 / 1000.,
                    flags: (v >> 13) as u8,
                }
            })
            .collect(),
        temperatures_c: (0..m).map(|i| s16at(28 + 2 * n + 2 * i)).collect(),
        protection_bits: format!("{:016X}", u64at(4)),
        warning_bits: format!("{:016X}", u64at(12)),
        mos_temperature_c: s16at(t),
        balance_temperature_c: s16at(t + 2),
        voltage_v: u16at(t + 4) as f64 / 100.,
        current_a: s16at(t + 6) as f64 / 10.,
        soc: u16at(t + 8),
        soh: u16at(t + 10),
        discharge_mos: data[t + 12],
        charge_mos: data[t + 13],
        balance_state: data[t + 14],
        bms_type: data[t + 15],
        capacity_ah: u32at(t + 16) as f64 / 1e6,
        remaining_ah: u32at(t + 20) as f64 / 1e6,
        cycle_ah: u32at(t + 24) as f64 / 1000.,
        power_w: u32at(t + 28) as i32,
        runtime_s: u32at(t + 32),
        total_discharge_ah: u32at(t + 62) as f64 / 1000.,
        total_charge_ah: u32at(t + 66) as f64 / 1000.,
        total_discharge_s: opt32(t + 70),
        total_charge_s: opt32(t + 74),
        balance_raw: u32at(t + 36),
        max_cell_v: u16at(t + 40) as f64 / 1000.,
        max_cell_index: u16at(t + 42),
        min_cell_v: u16at(t + 44) as f64 / 1000.,
        min_cell_index: u16at(t + 46),
        delta_v: u16at(t + 48) as f64 / 1000.,
        average_v: u16at(t + 50) as f64 / 1000.,
        battery_type: u16at(t + 60),
        charge_time_s: opt32(t + 78),
        last_charge_gap_s: opt32(t + 82),
        high_speed_current_a: opt16(t + 90).map(|v| (v as i16) as f64 / 10.),
        charger_voltage_v: opt16(t + 96).map(|v| v as f64 / 10.),
        charger_current_a: opt16(t + 98).map(|v| v as f64 / 10.),
        charger_connected: opt16(t + 100).map(|v| v & 0x8000 != 0),
        charge_remaining_min: opt16(t + 86),
        discharge_remaining_min: opt16(t + 88),
    })
}
#[derive(Default)]
pub struct Engine {
    parser: Parser,
}
impl Engine {
    pub fn feed(&mut self, bytes: &[u8]) -> serde_json::Value {
        let segments = self.parser.feed(bytes);
        let events: Vec<_> = segments
            .into_iter()
            .map(|s| {
                if s.function == 0x11 && !s.continuation {
                    match decode(&s.data) {
                        Ok(v) => {
                            serde_json::json!({"type":"snapshot","address":s.address,"data":v})
                        }
                        Err(e) => serde_json::json!({"type":"error","message":e}),
                    }
                } else {
                    serde_json::json!({"type":"segment","data":s})
                }
            })
            .collect();
        serde_json::json!({"events":events,"buffered":self.parser.buffered(),"discarded":self.parser.discarded})
    }
    pub fn reset(&mut self) {
        self.parser.reset();
    }
}
fn json_ptr(v: serde_json::Value) -> *mut c_char {
    CString::new(v.to_string()).unwrap().into_raw()
}
#[no_mangle]
pub extern "C" fn ant_engine_new() -> *mut Engine {
    Box::into_raw(Box::new(Engine::default()))
}
/// # Safety
/// `engine` is a live handle returned by ant_engine_new, used serially.
#[no_mangle]
pub unsafe extern "C" fn ant_engine_free(engine: *mut Engine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}
/// # Safety
/// The caller serializes access to a valid handle; bytes points to len readable bytes.
#[no_mangle]
pub unsafe extern "C" fn ant_engine_feed(
    engine: *mut Engine,
    bytes: *const u8,
    len: usize,
) -> *mut c_char {
    if engine.is_null() || bytes.is_null() || len > 65536 {
        return json_ptr(
            serde_json::json!({"events":[{"type":"error","message":"invalid FFI input"}]}),
        );
    }
    json_ptr((*engine).feed(std::slice::from_raw_parts(bytes, len)))
}
/// # Safety
/// Valid handle, no concurrent access.
#[no_mangle]
pub unsafe extern "C" fn ant_engine_reset(engine: *mut Engine) {
    if !engine.is_null() {
        (*engine).reset();
    }
}
/// # Safety
/// Pointer must be returned by this library and freed exactly once.
#[no_mangle]
pub unsafe extern "C" fn ant_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}
#[no_mangle]
pub extern "C" fn ant_read_request(address: u8) -> *mut c_char {
    json_ptr(serde_json::json!(read_realtime(address)))
}
/// Synthetic screenshot-inspired 21S packet. NOT captured from the user's device.
/// Only visible screenshot values are reproduced; hidden cell readings are synthesized.
pub fn demo_packet() -> Vec<u8> {
    let t = 28 + 42 + 8;
    let mut d = vec![0u8; t + 78 + 14];
    d[0] = 1;
    d[1] = 3;
    d[2] = 4;
    d[3] = 21;
    let cells: [u16; 21] = [
        3727, 3726, 3725, 3726, 3725, 3725, 3725, 3725, 3725, 3725, 3725, 3725, 3723, 3725, 3724,
        3724, 3724, 3724, 3724, 3724, 3724,
    ];
    for (i, v) in cells.iter().enumerate() {
        d[28 + 2 * i..30 + 2 * i].copy_from_slice(&v.to_le_bytes());
    }
    for (i, v) in [25i16, 24, -40, -40].iter().enumerate() {
        d[70 + 2 * i..72 + 2 * i].copy_from_slice(&v.to_le_bytes());
    }
    for (off, value) in [
        (0, 24u16),
        (2, 25),
        (4, 7822),
        (6, 1),
        (8, 56),
        (10, 100),
        (40, 3727),
        (42, 1),
        (44, 3723),
        (46, 13),
        (48, 4),
        (50, 3724),
        (60, 0xfaf1),
        (86, 0),
        (88, 1561),
    ] {
        d[t + off..t + off + 2].copy_from_slice(&value.to_le_bytes());
    }
    d[t + 12] = 1;
    d[t + 13] = 1;
    for (off, value) in [
        (16, 170_000_000u32),
        (20, 96_200_000),
        (24, 3_230_000),
        (28, 7),
        (32, 8328),
    ] {
        d[t + off..t + off + 4].copy_from_slice(&value.to_le_bytes());
    }
    build(0xa1, 0x11, 0, 0, &d).unwrap()
}
#[no_mangle]
pub extern "C" fn ant_demo_frame() -> *mut c_char {
    json_ptr(serde_json::json!(demo_packet()))
}
