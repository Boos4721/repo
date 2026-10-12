use ant_core::*;
fn hex(s: &str) -> Vec<u8> {
    s.split_whitespace()
        .map(|b| u8::from_str_radix(b, 16).unwrap())
        .collect()
}
fn real() -> Vec<u8> {
    hex(include_str!("real-frame.hex"))
}
#[test]
fn known_request_crc() {
    assert_eq!(read_realtime(0xa1), hex("7E A1 01 00 00 F5 58 62 AA 55"));
    assert_eq!(
        build(0xa1, 2, 104, 32, &[]).unwrap(),
        hex("7E A1 02 68 00 20 18 65 AA 55")
    );
}
#[test]
fn hardware_capture() {
    let frames = Parser::default().feed(&real());
    assert_eq!(frames.len(), 1);
    let s = decode(&frames[0].data).unwrap();
    assert_eq!(s.cells.len(), 20);
    assert_eq!(s.voltage_v, 85.36);
    assert_eq!(s.current_a, 0.1);
    assert_eq!(s.soc, 100);
    assert_eq!(s.runtime_s, 35516411);
    assert_eq!(s.temperatures_c, vec![23, 23, 23, 22]);
    assert_eq!(s.max_cell_index, 6);
    assert_eq!(s.delta_v, 0.006);
    assert!((s.capacity_ah - 113.0).abs() < 1e-9);
    assert_eq!(s.charge_time_s, Some(0));
}
#[test]
fn every_split() {
    let frame = real();
    for split in 0..=frame.len() {
        let mut p = Parser::default();
        let mut out = p.feed(&frame[..split]);
        out.extend(p.feed(&frame[split..]));
        assert_eq!(out.len(), 1, "split {split}");
        assert_eq!(p.buffered(), 0);
    }
}
#[test]
fn bytewise() {
    let mut p = Parser::default();
    let mut out = vec![];
    for b in real() {
        out.extend(p.feed(&[b]));
    }
    assert_eq!(out.len(), 1);
}
#[test]
fn combined_auth() {
    let wire = hex("7E A1 43 4A 01 02 01 00 9D 5B FF 05 00 00 20 31 AA 55");
    for split in 0..=wire.len() {
        let mut p = Parser::default();
        let mut out = p.feed(&wire[..split]);
        out.extend(p.feed(&wire[split..]));
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].register, 330);
        assert_eq!(out[1].function, 0xff);
        assert_eq!(out[1].address, 0xa1);
        assert!(out[1].continuation);
    }
}
#[test]
fn noise_crc_and_recovery() {
    let mut bad = real();
    bad[40] ^= 1;
    let mut wire = vec![0, 0x55, 0x7e, 0, 0, 0, 0, 0, 0, 0];
    wire.extend(bad);
    wire.extend(real());
    let out = Parser::default().feed(&wire);
    assert_eq!(out.len(), 1);
}
#[test]
fn incomplete_trailer_never_delivered() {
    let frame = real();
    let mut p = Parser::default();
    assert!(p.feed(&frame[..frame.len() - 1]).is_empty());
    assert_eq!(p.feed(&frame[frame.len() - 1..]).len(), 1);
}
#[test]
fn session_reset_discards_partial() {
    let frame = real();
    let mut p = Parser::default();
    p.feed(&frame[..50]);
    p.reset();
    assert!(p.feed(&frame[50..]).is_empty());
    assert_eq!(p.feed(&frame).len(), 1);
}
#[test]
fn truncation_and_unknown_bits() {
    let frames = Parser::default().feed(&real());
    let mut data = frames[0].data.clone();
    for len in 0..146 {
        assert!(decode(&data[..len]).is_err());
    }
    data.truncate(146);
    let s = decode(&data).unwrap();
    assert_eq!(s.charge_time_s, None);
    assert_eq!(s.total_discharge_s, None);
    assert_eq!(s.total_charge_s, None);
    assert_eq!(s.warning_bits, "0000000005800001");
}
#[test]
fn signed_fields_flags() {
    let mut data = Parser::default().feed(&real())[0].data.clone();
    data[28..30].copy_from_slice(&(0xe000u16 | 4200).to_le_bytes());
    data[68..70].copy_from_slice(&(-40i16).to_le_bytes());
    data[82..84].copy_from_slice(&(-120i16).to_le_bytes());
    let s = decode(&data).unwrap();
    assert_eq!(s.cells[0].voltage_v, 4.2);
    assert_eq!(s.cells[0].flags, 7);
    assert_eq!(s.temperatures_c[0], -40);
    assert_eq!(s.current_a, -12.);
}

#[test]
fn shorter_core_preserves_statistics_and_optional_times() {
    let mut data = Parser::default().feed(&real())[0].data.clone();
    let t = 28 + 2 * data[3] as usize + 2 * data[2] as usize;
    data[t + 62..t + 66].copy_from_slice(&123456u32.to_le_bytes());
    data[t + 66..t + 70].copy_from_slice(&987654u32.to_le_bytes());
    data[t + 70..t + 74].copy_from_slice(&90061u32.to_le_bytes());
    data.truncate(t + 74);
    let s = decode(&data).unwrap();
    assert_eq!(s.total_discharge_ah, 123.456);
    assert_eq!(s.total_charge_ah, 987.654);
    assert_eq!(s.total_discharge_s, Some(90061));
    assert_eq!(s.total_charge_s, None);
    assert_eq!(s.charge_time_s, None);
    data.truncate(t + 70);
    let short_frame = build(0xa1, 0x11, 0, 0, &data).unwrap();
    let event = Engine::default().feed(&short_frame);
    assert_eq!(event["events"][0]["type"], "snapshot");
}
#[test]
fn coalesced_packets() {
    let mut bytes = real();
    bytes.extend(real());
    assert_eq!(Parser::default().feed(&bytes).len(), 2);
}
#[test]
fn register_endian() {
    let frame = build(0xa0, 0x59, 0xf0, 0, &[0x10]).unwrap();
    assert_eq!(&frame[3..5], &[0, 0xf0]);
    assert_eq!(Parser::default().feed(&frame)[0].register, 0xf0);
}
#[test]
fn bounded_noise() {
    let mut p = Parser::default();
    p.feed(&vec![0x7e; 100000]);
    assert!(p.buffered() <= 4096);
}

#[test]
fn screenshot_profile_is_synthetic_and_consistent() {
    let segments = Parser::default().feed(&demo_packet());
    let s = decode(&segments[0].data).unwrap();
    assert_eq!(s.cells.len(), 21);
    assert_eq!(s.voltage_v, 78.22);
    assert_eq!(s.soc, 56);
    assert_eq!(s.capacity_ah, 170.);
    assert_eq!(s.remaining_ah, 96.2);
    assert_eq!(s.discharge_remaining_min, Some(1561));
    assert_eq!(s.temperatures_c, vec![25, 24, -40, -40]);
    assert_eq!(s.mos_temperature_c, 24);
    assert_eq!(s.balance_temperature_c, 25);
    assert_eq!(s.max_cell_index, 1);
    assert_eq!(s.min_cell_index, 13);
    assert_eq!(s.delta_v, 0.004);
    assert!((s.cells.iter().map(|c| c.voltage_v).sum::<f64>() - s.voltage_v).abs() < 1e-8);
    assert_eq!(s.charger_connected, None);
}
#[test]
fn optional_extensions_at_every_boundary() {
    let mut data = Parser::default().feed(&real())[0].data.clone();
    let t = 76;
    data.resize(t + 102, 0);
    data[t + 90..t + 92].copy_from_slice(&(-25i16).to_le_bytes());
    data[t + 96..t + 98].copy_from_slice(&880u16.to_le_bytes());
    data[t + 98..t + 100].copy_from_slice(&300u16.to_le_bytes());
    data[t + 100..t + 102].copy_from_slice(&0x8001u16.to_le_bytes());
    for len in t + 78..=t + 102 {
        let s = decode(&data[..len]).unwrap();
        assert_eq!(s.charge_time_s.is_some(), len >= t + 82);
        assert_eq!(s.last_charge_gap_s.is_some(), len >= t + 86);
        assert_eq!(s.charge_remaining_min.is_some(), len >= t + 88);
        assert_eq!(s.discharge_remaining_min.is_some(), len >= t + 90);
        assert_eq!(s.high_speed_current_a.is_some(), len >= t + 92);
        assert_eq!(s.charger_voltage_v.is_some(), len >= t + 98);
        assert_eq!(s.charger_current_a.is_some(), len >= t + 100);
        assert_eq!(s.charger_connected.is_some(), len >= t + 102);
    }
    let s = decode(&data).unwrap();
    assert_eq!(s.high_speed_current_a, Some(-2.5));
    assert_eq!(s.charger_voltage_v, Some(88.));
    assert_eq!(s.charger_current_a, Some(30.));
    assert_eq!(s.charger_connected, Some(true));
}
