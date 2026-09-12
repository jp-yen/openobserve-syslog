-- cisco.lua - Port 3514: Cisco デバイスログパーサー
package.path = package.path .. ";/fluent-bit/scripts/?.lua"
local common = require("common")

-- メッセージ本文の先頭から Cisco タイムスタンプを検出して除去する
-- 対応形式: [seqNNN:] [*.]? Month DD [YYYY] HH:MM:SS[.mmm] [TZ]:
-- 戻り値: gen_ts (Unix epoch float または nil), タイムスタンプ除去後のメッセージ
local function extract_cisco_timestamp(msg)
    local month, day, year, tpart, tz, rest

    -- Cisco IOS は "<pri>seq1: host: seq2: *Month DD ..." のように
    -- メッセージ本文の先頭にさらにシーケンス番号が付くことがある
    -- 例: "000072: *Aug 23 16:55:41.355 JST: %SEC_LOGIN-5-LOGIN_SUCCESS: ..."
    -- その場合は先頭の "NNN: " または "NNN: *" を読み飛ばしてからタイムスタンプを探す
    local try_msg = msg:match("^[0-9]+:%s*(.*)") or msg

    -- 形式 1: Month DD YYYY HH:MM:SS TZ:
    month, day, year, tpart, tz, rest =
        try_msg:match("^[*.%s]*([A-Za-z]+)%s+([0-9]+)%s+([0-9]+)%s+([0-9:.]+)%s+([A-Za-z]+):%s+(.*)")
    -- 形式 2: Month DD YYYY HH:MM:SS: (TZなし)
    if not rest then
        month, day, year, tpart, rest =
            try_msg:match("^[*.%s]*([A-Za-z]+)%s+([0-9]+)%s+([0-9]+)%s+([0-9:.]+):%s+(.*)")
    end
    -- 形式 3: Month DD HH:MM:SS TZ:
    if not rest then
        month, day, tpart, tz, rest =
            try_msg:match("^[*.%s]*([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+)%s+([A-Za-z]+):%s+(.*)")
    end
    -- 形式 4: Month DD HH:MM:SS: (TZなし)
    if not rest then
        month, day, tpart, rest =
            try_msg:match("^[*.%s]*([A-Za-z]+)%s+([0-9]+)%s+([0-9:.]+):%s+(.*)")
    end

    if not rest then return nil, msg end

    local mn_key = month:sub(1,1):upper() .. month:sub(2,3):lower()
    local mn     = common.month_map[mn_key] or month
    local yr     = year or os.date("%Y")
    local tz_str = (tz == "UTC" or tz == "GMT") and "Z" or "+09:00"

    local gen_ts
    if #mn == 2 then
        local ts_iso = string.format("%s-%s-%02dT%s%s", yr, mn, tonumber(day) or 1, tpart, tz_str)
        gen_ts = common.iso8601_to_unix(ts_iso)
    end
    return gen_ts, rest
end

-- %FACILITY-SEV-MNEMONIC: 形式の Cisco システムメッセージ識別子をパースして out を更新する
-- 戻り値: message_body (識別子の後続メッセージ本文) または nil
local function parse_cisco_facility_msg(msg, raw, out)
    -- メッセージ本文から %FAC-SEV-MNEM: を検索
    local fac, sev, mnem, body = msg:match("^%%([A-Z0-9_]+)%-([0-9]+)%-([A-Z0-9_]+):%s*(.*)")
    if fac then
        out["cisco_facility"] = fac
        out["cisco_severity"] = sev
        out["cisco_mnemonic"] = mnem
        out["facility"]       = string.upper(fac)
        out["program"]        = string.format("%%%s-%s-%s", fac, sev, mnem)
        out["priority"]       = common.get_priority(sev)
        return body ~= "" and body or nil
    end
    -- 本文に含まれない場合は生ログ全体から検索 (出力フィールドのみ設定)
    local r_fac, r_sev, r_mnem = raw:match("%%([A-Z0-9_]+)%-([0-9]+)%-([A-Z0-9_]+)")
    if r_fac then
        out["cisco_facility"] = r_fac
        out["cisco_severity"] = r_sev
        out["cisco_mnemonic"] = r_mnem
        out["facility"]       = string.upper(r_fac)
        out["program"]        = string.format("%%%s-%s-%s", r_fac, r_sev, r_mnem)
        out["priority"]       = common.get_priority(r_sev)
    end
    return nil
end

function process(tag, timestamp, record)
    local out, raw, host_from = common.create_base_record(tag, timestamp, record, 3514, "s_cisco")

    if raw == "" then return 1, timestamp, out end
    out["raw_message"] = raw

    local msg        = raw
    local parse_type = "Cisco_FALLBACK"
    local pri, seq1, cisco_host, sd, seq2

    -- パターン 1a: <pri>seq: host: [syslog@9...]: seq2: msg
    pri, seq1, cisco_host, sd, seq2, msg =
        raw:match("^<([0-9]+)>([0-9]+):%s+([^: ]+):%s+(%[syslog@9[^%]]*%]):%s+([0-9]+):%s+(.*)")
    if msg then parse_type = "Cisco_PRI_Seq_Host_SD_Seq" end

    -- パターン 1b: <pri>seq: host: [syslog@9...]: msg
    if not msg then
        pri, seq1, cisco_host, sd, msg =
            raw:match("^<([0-9]+)>([0-9]+):%s+([^: ]+):%s+(%[syslog@9[^%]]*%]):%s+(.*)")
        if msg then parse_type = "Cisco_PRI_Seq_Host_SD" end
    end

    -- パターン 2a: <pri>seq: [syslog@9...]: seq2: msg (ホスト名なし)
    if not msg then
        pri, seq1, sd, seq2, msg =
            raw:match("^<([0-9]+)>([0-9]+):%s+(%[syslog@9[^%]]*%]):%s+([0-9]+):%s+(.*)")
        if msg then parse_type = "Cisco_PRI_Seq_SD_Seq" end
    end

    -- パターン 2b: <pri>seq: [syslog@9...]: msg (ホスト名なし, seq2なし)
    if not msg then
        pri, seq1, sd, msg =
            raw:match("^<([0-9]+)>([0-9]+):%s+(%[syslog@9[^%]]*%]):%s+(.*)")
        if msg then parse_type = "Cisco_PRI_Seq_SD" end
    end

    -- パターン 3a: <pri>seq: host: seq2: msg (seq2あり - Cisco IOS の典型形式)
    if not msg then
        pri, seq1, cisco_host, seq2, msg =
            raw:match("^<([0-9]+)>([0-9]+):%s+([^: ]+):%s+([0-9]+):%s+(.*)")
        if msg then parse_type = "Cisco_PRI_Seq_Host_Seq" end
    end

    -- パターン 3b: <pri>seq: host: msg (seq2なし)
    if not msg then
        pri, seq1, cisco_host, msg =
            raw:match("^<([0-9]+)>([0-9]+):%s+([^: ]+):%s+(.*)")
        if msg then parse_type = "Cisco_PRI_Seq_Host" end
    end

    -- パターン 4: <pri>seq: msg
    if not msg then
        pri, seq1, msg = raw:match("^<([0-9]+)>([0-9]+):%s+(.*)")
        if msg then parse_type = "Cisco_PRI_Seq" end
    end

    -- パターン 5: <pri>host: msg
    if not msg then
        pri, cisco_host, msg = raw:match("^<([0-9]+)>([^: ]+):%s+(.*)")
        if msg then parse_type = "Cisco_PRI_Host" end
    end

    -- パターン 6: seq: host: msg (PRIなし)
    if not msg then
        seq1, cisco_host, msg = raw:match("^([0-9]+):%s+([^: ]+):%s+(.*)")
        if msg then parse_type = "Cisco_Seq_Host" end
    end

    -- パターン 7: seq: msg (PRIなし)
    if not msg then
        seq1, msg = raw:match("^([0-9]+):%s+(.*)")
        if msg then parse_type = "Cisco_Seq" end
    end

    if not msg then msg = raw end

    -- PRI から facility / priority を設定する
    if pri then
        out["facility"], out["priority"] = common.parse_syslog_pri(pri)
    end

    -- ログ内ホスト名の設定
    if cisco_host and cisco_host ~= "" then out["host"] = cisco_host end
    common.normalize_host_from(out)

    -- 構造化データ (sd) の解析 (s_sn, s_id 等)
    if sd then
        local s_sn = sd:match('s_sn="?([0-9]+)"?')
        local s_id = sd:match('s_id%s*=%s*"([^"]+)"')
        if s_sn then out["s_sn"] = s_sn end
        if s_id then out["s_id"] = s_id end
    end

    -- シーケンス番号の設定 (seq2 を優先)
    out["seq"] = seq2 or seq1

    -- 構造化データの残骸を msg から除去する
    msg = msg:gsub("^%[syslog@9[^%]]*%]:%s*", "")
    msg = msg:gsub("^%]:%s*", "")

    -- Cisco タイムスタンプの抽出と除去
    local gen_ts
    gen_ts, msg = extract_cisco_timestamp(msg)

    -- %FACILITY-SEV-MNEMONIC: 識別子のパースと program / priority の設定
    local body = parse_cisco_facility_msg(msg, raw, out)
    if body then msg = body end

    -- FACILITY メッセージが含まれていれば parse_type を昇格する
    if parse_type == "Cisco_FALLBACK" and
       (out["cisco_facility"] or raw:match("%%[A-Z0-9_]+%-[0-9]+%-[A-Z0-9_]+")) then
        parse_type = "Cisco_FACILITY"
    end

    out["parse_type"] = parse_type
    out["message"]    = common.trim(msg)

    return 1, (gen_ts or timestamp), out
end
