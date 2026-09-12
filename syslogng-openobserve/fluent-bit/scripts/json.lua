-- json.lua - Port 6514: JSON / logfmt 構造化ログパーサー
-- 対象: Fluent Bit 転送ログ / Docker コンテナログ / アプリケーション構造化ログ
package.path = package.path .. ";/fluent-bit/scripts/?.lua"
local common = require("common")

-- Fluent Bit 内部フィールドおよび独自管理フィールド (上書き禁止)
local PROTECTED_KEYS = {
    source      = true, host        = true, host_from   = true,
    priority    = true, parse_type  = true, raw_message = true,
    remote_addr = true, source_address = true,
}

-- record 内のスカラー値 (文字列/数値/真偽値) を out にコピーする
-- PROTECTED_KEYS に含まれるキーはスキップする
local function copy_scalar_fields(src, dst)
    for k, v in pairs(src) do
        if not PROTECTED_KEYS[k] then
            local t = type(v)
            if t == "string" or t == "number" or t == "boolean" then
                dst[k] = v
            end
        end
    end
end

-- raw が JSON 文字列の場合にデコードを試みる
-- cjson が利用可能なら優先し、なければ純 Lua の common.json_decode を使用する
local function try_decode_json(raw)
    if not raw or raw == "" then return nil end
    local trimmed = common.trim(raw)
    if trimmed == "" or (trimmed:sub(1,1) ~= "{" and trimmed:sub(1,1) ~= "[") then
        return nil
    end
    if common.cjson_ok then
        local ok, decoded = pcall(common.cjson.decode, trimmed)
        if ok and type(decoded) == "table" then return decoded end
    end
    -- 純 Lua デコーダーによる完全パース
    local decoded = common.json_decode(trimmed)
    if decoded and type(decoded) == "table" then return decoded end

    -- 最終フォールバック (json_get)
    return {
        log            = common.json_get(trimmed, "log") or common.json_get(trimmed, "message") or common.json_get(trimmed, "@message"),
        program        = common.json_get(trimmed, "program"),
        system         = common.json_get(trimmed, "system"),
        container_name = common.json_get(trimmed, "container_name"),
        container_id   = common.json_get(trimmed, "container_id"),
        host           = common.json_get(trimmed, "host") or common.json_get(trimmed, "hostname"),
        date           = common.json_get(trimmed, "date"),
        level          = common.json_get(trimmed, "level") or common.json_get(trimmed, "@level"),
        logger         = common.json_get(trimmed, "logger"),
    }
end

-- メッセージ本文から ISO タイムスタンプ + ログレベルを検出して取り出す
-- 例: "2026-08-22T01:12:12.287797Z  INFO influxdb3_wal::object_store: ..."
-- 戻り値: gen_ts (Unix epoch float または nil), pri (文字列または nil), clean_msg
local function parse_msg_iso_header(msg)
    local ts_str, lvl_str, rest =
        msg:match("^(%d%d%d%d%-%d%d%-%d%dT%S+)%s+%[?([%a]+)%]?%s*:?%s*(.*)")
    if not ts_str then return nil, nil, msg end
    local gen_ts = common.iso8601_to_unix(ts_str)
    local pri    = common.get_priority(lvl_str)
    return gen_ts, pri, common.trim(rest)
end

-- メッセージ本文から "t=... level=..." 形式のプレフィックスを除去する
-- (syslog-ng r_clean_message 相当)
local function strip_logfmt_header(msg)
    local stripped = msg:gsub("^t=%d%d%d%d%-%d%d%-%d%dT%S+%s+level=[%a]+%s*", "")
    return (stripped ~= msg) and common.trim(stripped) or msg
end

-- logfmt 形式 (msg="..." を含む key=value) をパースして out を更新する
-- 戻り値: gen_ts (Unix epoch float または nil), pri (文字列または nil), actual_msg
local function parse_logfmt(msg, out)
    if not msg:find("[%w_%.%-]+=") then return nil, nil, msg end
    local kv = common.parse_kv(msg)
    local actual_msg = kv["msg"] or kv["message"]
    if not actual_msg then return nil, nil, msg end
    actual_msg = common.trim(actual_msg)

    local gen_ts, pri
    for k, v in pairs(kv) do
        if k == "msg" or k == "message" then
            -- 処理済み
        elseif k == "level" or k == "severity" then
            pri = common.get_priority(v)
        elseif k == "t" or k == "ts" or k == "time" then
            gen_ts = common.iso8601_to_unix(v) or common.epoch_to_unix(v)
        elseif not PROTECTED_KEYS[k] and not out[k] then
            out[k] = v
        end
    end
    return gen_ts, pri, actual_msg
end

function process(tag, timestamp, record)
    local out, raw, host_from, port, transport =
        common.create_base_record(tag, timestamp, record, 6514, "s_fluent_bit")
    local new_ts, pri

    -- 生の受信メッセージを raw_message として保存
    out["raw_message"] = raw ~= "" and raw or nil

    -- Fluent Bit が付与するメタフィールドをスカラー値のみコピー
    copy_scalar_fields(record, out)

    -- raw が JSON の場合はデコードして out にマージする
    local parsed = try_decode_json(raw)
    if parsed then copy_scalar_fields(parsed, out) end

    -- host の決定: 明示指定 (host/hostname) > 接続元IP (host_from) > システム識別子 (system)
    local explicit_host = (parsed and (parsed["host"] or parsed["hostname"]))
                       or record["host"] or record["hostname"]
    if explicit_host and explicit_host ~= "" then
        out["host"] = explicit_host
    elseif host_from and host_from ~= "" then
        out["host"] = host_from
    elseif out["system"] and out["system"] ~= "" then
        out["host"] = out["system"]
    end
    out["host_from"] = host_from

    -- source を正しい値で上書き
    out["source"] = string.format("s_fluent_bit/%d/%s", port, transport)

    -- メッセージ本文の決定 (parsed["log"] または parsed["message"] または record/raw)
    local msg = nil
    if parsed and (parsed["log"] or parsed["message"]) then
        msg = common.trim(parsed["log"] or parsed["message"])
    else
        msg = common.trim(out["log"] or out["message"] or raw)
    end

    -- ログ本文 (msg) 自体がネストした JSON 文字列の場合、さらにデコードして展開する
    local nested_json = try_decode_json(msg)
    if nested_json then
        copy_scalar_fields(nested_json, out)
        if nested_json["@level"] or nested_json["level"] then
            pri = nested_json["@level"] or nested_json["level"]
        end
        if nested_json["@timestamp"] or nested_json["timestamp"] or nested_json["time"] then
            local n_ts = common.iso8601_to_unix(nested_json["@timestamp"] or nested_json["timestamp"] or nested_json["time"])
            if n_ts then new_ts = n_ts end
        end
        local n_msg = nested_json["@message"] or nested_json["msg"] or nested_json["message"] or nested_json["log"]
        if n_msg and n_msg ~= "" then
            msg = common.trim(n_msg)
        end
    end
    out["message"] = msg

    -- priority の初期値 (JSON フィールドから)
    pri = pri or record["level"] or record["severity"]
          or (parsed and (parsed["level"] or parsed["severity"]))

    -- メッセージ本文の詳細パース
    if msg and msg ~= "" then
        -- 1. ISO タイムスタンプ + ログレベルのヘッダー除去 (InfluxDB 等)
        local ts_from_msg, pri_from_msg, clean_msg = parse_msg_iso_header(msg)
        if clean_msg ~= msg then
            if ts_from_msg then new_ts = ts_from_msg end
            if pri_from_msg then pri = pri_from_msg end
            msg = clean_msg
            out["message"] = msg
        end

        -- 2. "t=... level=..." プレフィックスの除去
        local stripped = strip_logfmt_header(msg)
        if stripped ~= msg then
            msg = stripped
            out["message"] = msg
        end

        -- 3. logfmt 形式 (msg="..." を含む) のパース
        local ts_from_kv, pri_from_kv, kv_msg = parse_logfmt(msg, out)
        if kv_msg and kv_msg ~= msg then
            if ts_from_kv and not new_ts then new_ts = ts_from_kv end
            if pri_from_kv then pri = pri_from_kv end
            msg = kv_msg
            out["message"] = msg
        end
    end

    -- タイムスタンプ: JSON の date/timestamp/time フィールドをフォールバックとして使用
    if not new_ts then
        local raw_date = out["date"] or out["timestamp"] or out["time"]
        if raw_date then
            new_ts = common.epoch_to_unix(raw_date) or common.iso8601_to_unix(tostring(raw_date))
        end
    end

    -- date フィールドが数値エポックの場合は ISO 8601 文字列に正規化する
    if out["date"] then
        local date_epoch = common.epoch_to_unix(out["date"])
        if date_epoch then out["date"] = common.unix_to_iso8601(date_epoch) end
    end

    -- priority のフォールバック: メッセージ本文からの検出
    if not pri or pri == "" then
        pri = tostring(msg):match("level=([a-zA-Z]+)")
             or tostring(msg):match("^[0-9T:%-+%.]+%s+([A-Z]+)%s+")
    end
    out["priority"] = common.get_priority(pri) or "INFO"
    out["message"]  = common.trim(msg or out["message"] or raw)

    -- raw が JSON でない場合: RFC 5424 / RFC 3164 / Syslog 形式のフォールバック判定
    local p_type = nil
    if not parsed then
        local r5 = common.parse_rfc5424(raw)
        if r5 then
            out["facility"]        = r5.facility
            out["priority"]        = r5.priority
            if r5.host then out["host"] = r5.host end
            out["program"]         = r5.program
            out["pid"]             = r5.pid
            out["msgid"]           = r5.msgid
            out["structured_data"] = r5.structured_data
            out["message"]         = r5.message and common.trim(r5.message) or raw
            if r5.gen_ts then new_ts = r5.gen_ts end
            p_type = "RFC5424"
        else
            local r3 = common.parse_rfc3164(raw)
            if r3 then
                out["facility"]   = r3.facility
                out["priority"]   = r3.priority
                if r3.host then out["host"] = r3.host end
                out["program"]    = r3.program
                out["pid"]        = r3.pid
                out["message"]    = r3.message and common.trim(r3.message) or raw
                if r3.gen_ts then new_ts = r3.gen_ts end
                p_type = r3.parse_type or "RFC3164"
            end
        end
    end
    common.normalize_host_from(out)

    -- parse_type の決定
    out["parse_type"] = p_type
                        or (parsed and "JSON")
                        or (msg and msg:find("[%w_%.%-]+=") and "LOGFMT")
                        or "JSON_FALLBACK"

    -- 内部フィールドの除去
    out["log"]            = nil
    out["remote_addr"]    = nil
    out["source_address"] = nil

    return 1, (new_ts or timestamp), out
end
