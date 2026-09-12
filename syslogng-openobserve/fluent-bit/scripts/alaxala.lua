-- alaxala.lua - Port 7514: AlaxalA スイッチログパーサー
--
-- 対応ログ形式 (メッセージ例):
--
-- 1. AX2600S 運用ログ (yyyy/mm/dd, スタック状態あり)
--    <187>EVT 2026/08/22 12:00:00 01S R8 PORT PORT:01/0/1 25040200 0000:000000000000 Port Link UP
--    EVT 2026/08/22 12:00:00 01S E3 EQUIPMENT 00000003 0000:000000000000 Failed in accumulated running time access to main.
--
-- 2. AX3660S 運用ログ (mm/dd, スタック状態あり)
--    <187>EVT 08/22 12:00:00 01S R8 PORT PORT:01/0/1 25040200 0000:000000000000 Port Link UP
--    EVT 08/22 12:00:00 01S E3 EQUIPMENT 00000003 0000:000000000000 Failed in accumulated running time access to main.
--
-- 3. AX3630S 運用ログ (mm/dd, スタック状態なし)
--    <187>EVT 08/22 12:00:00 R8 PORT PORT:01/0/1 25040200 0000:000000000000 Port Link UP
--    EVT 08/22 12:00:00 E3 EQUIPMENT 00000003 0000:000000000000 Failed in accumulated running time access to main.
--
-- 4. AX2100S / AX2200S / AX1240S 運用ログ (EVT LEVEL yy/mm/dd hh:mm:ss TASK Message)
--    EVT INFO 26/08/22 12:00:00 PORT Port 1/1 link up
--    <187>EVT WARN 26/08/22 12:00:00 POE PoE power supply port 1/2 overload
--
-- 5. 画面出力形式 (log_type なし)
--    2026/08/22 12:00:00 01S E3 EQUIPMENT 00000003 0000:000000000000 Console event message
--    08/22 12:00:00 E3 EQUIPMENT 00000003 0000:000000000000 Console event message
--
-- 6. メッセージテキスト運用ログ (ルーティングプロトコル情報等)
--    EVT 08/22 12:00:00 RTM: BGP neighbor 10.0.0.1 Up
--    EVT 08/22 12:00:00 TRO: Tracking object 1 state changed to Down
--
-- 7. 従来 AX シリーズ形式
--    LOG 08/22 11:00:00 I001 SYSTEM test legacy alaxala
--
-- 8. タイムスタンプなし簡易形式
--    LOG E1 SYSTEM Power supply unit failure detected
--
package.path = package.path .. ";/fluent-bit/scripts/?.lua"
local common = require("common")

-- AlaxalA severity / event level -> syslog severity 変換マップ
local SEVERITY_MAP = {
    -- AX2100S 系 (英語レベル名)
    FATAL = "EMERG",  CRITC = "CRIT",  ERROR = "ERR",
    WARN  = "WARNING", INFO  = "INFO",
    -- AX2600S / AX3660S / AX3630S 系 (EN コード)
    E9 = "EMERG",  E8 = "ALERT",
    E7 = "CRIT",   E6 = "CRIT",
    E5 = "ERR",    E4 = "ERR",
    E3 = "WARNING",
    R8 = "NOTICE", R7 = "NOTICE", R6 = "NOTICE", R5 = "NOTICE",
    -- 従来形式 (1文字)
    E = "ERR",  W = "WARNING",  I = "INFO",  D = "DEBUG",  R = "NOTICE",
}

-- date_part 文字列から ISO 8601 形式のタイムスタンプを生成して gen_ts を返す
-- 対応日付形式: yyyy/mm/dd, yy/mm/dd (AX2100S), mm/dd
local function parse_alaxala_timestamp(date_part, time_part)
    if not date_part or not time_part then return nil end

    -- yyyy/mm/dd
    local y, m, d = date_part:match("^(%d%d%d%d)[/%-](%d%d)[/%-](%d%d)")
    if y then
        return common.iso8601_to_unix(string.format("%s-%s-%sT%s+09:00", y, m, d, time_part))
    end

    -- yy/mm/dd (AX2100S: 70以上は 1900年代、それ以外は 2000年代)
    local y2, m2, d2 = date_part:match("^(%d%d)[/%-](%d%d)[/%-](%d%d)")
    if y2 then
        local y4 = (tonumber(y2) >= 70) and ("19" .. y2) or ("20" .. y2)
        return common.iso8601_to_unix(string.format("%s-%s-%sT%s+09:00", y4, m2, d2, time_part))
    end

    -- mm/dd (年は現在年を使用)
    local mm, dd = date_part:match("^(%d%d)[/%-](%d%d)")
    if mm then
        return common.iso8601_to_unix(string.format("%s-%s-%sT%s+09:00", os.date("%Y"), mm, dd, time_part))
    end

    return nil
end

-- パターンマッチを試みて、成功した場合は is_matched = true を返すヘルパー
-- fields テーブルへの多値代入を統一するためのクロージャ形式
-- 注: Lua では多値代入をまとめるネイティブな方法がないため、
--     各パターンは直接 process() 内で記述し、このヘルパーで is_matched だけ管理する
local function matched(val)
    return val ~= nil
end

function process(tag, timestamp, record)
    local out, raw, host_from, port, transport =
        common.create_base_record(tag, timestamp, record, 7514, "s_alaxala")

    if raw == "" then return 1, timestamp, out end
    out["raw_message"] = raw

    local msg = raw

    -- オプションの <PRI> ヘッダーを除去して facility / priority を設定する
    local pri_str, rest = raw:match("^<([0-9]+)>(.*)")
    if pri_str then
        local fac, sev = common.parse_syslog_pri(pri_str)
        if fac then out["facility"] = fac end
        if sev then out["priority"] = sev end
        msg = rest
    end

    -- パース結果を格納するローカル変数
    local log_type, date_part, time_part, sw_state, ev_level
    local module, if_id, msg_id, add_info, detail
    local is_matched = false

    -- -------------------------------------------------------------------------
    -- グループ A: kkk 付き運用ログ (AX2600S / AX3660S / AX3630S / AX2100S)
    -- -------------------------------------------------------------------------

    -- A1a: AX2600S (yyyy/mm/dd, IF識別子あり, wwwあり)
    log_type, date_part, time_part, sw_state, ev_level, module, if_id, msg_id, add_info, detail =
        msg:match("^([A-Z]+)%s+(%d%d%d%d[/%-]%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+(PORT:[%w_/%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
    is_matched = matched(log_type)

    -- A1b: AX2600S (yyyy/mm/dd, IF識別子なし, wwwあり)
    if not is_matched then
        log_type, date_part, time_part, sw_state, ev_level, module, msg_id, add_info, detail =
            msg:match("^([A-Z]+)%s+(%d%d%d%d[/%-]%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- A2a: AX3660S (mm/dd, IF識別子あり, wwwあり)
    if not is_matched then
        log_type, date_part, time_part, sw_state, ev_level, module, if_id, msg_id, add_info, detail =
            msg:match("^([A-Z]+)%s+(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+(PORT:[%w_/%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- A2b: AX3660S (mm/dd, IF識別子なし, wwwあり)
    if not is_matched then
        log_type, date_part, time_part, sw_state, ev_level, module, msg_id, add_info, detail =
            msg:match("^([A-Z]+)%s+(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- A3a: AX3630S (mm/dd, IF識別子あり, wwwなし)
    if not is_matched then
        log_type, date_part, time_part, ev_level, module, if_id, msg_id, add_info, detail =
            msg:match("^([A-Z]+)%s+(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([ER][0-9])%s+([%w_%-]+)%s+(PORT:[%w_/%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- A3b: AX3630S (mm/dd, IF識別子なし, wwwなし)
    if not is_matched then
        log_type, date_part, time_part, ev_level, module, msg_id, add_info, detail =
            msg:match("^([A-Z]+)%s+(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([ER][0-9])%s+([%w_%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- A4: AX2100S (EVT LEVEL yy/mm/dd hh:mm:ss TASK Message)
    if not is_matched then
        log_type, ev_level, date_part, time_part, module, detail =
            msg:match("^([A-Z]+)%s+([A-Z]+)%s+(%d%d[/%-]%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([%w_%-]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- -------------------------------------------------------------------------
    -- グループ B: 画面出力形式 (log_type なし)
    -- -------------------------------------------------------------------------

    -- B1a: AX2600S 画面出力 (yyyy/mm/dd, IF識別子あり, wwwあり)
    if not is_matched then
        date_part, time_part, sw_state, ev_level, module, if_id, msg_id, add_info, detail =
            msg:match("^(%d%d%d%d[/%-]%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+(PORT:[%w_/%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        if matched(date_part) then is_matched = true; log_type = "EVENT" end
    end

    -- B1b: AX2600S 画面出力 (yyyy/mm/dd, IF識別子なし, wwwあり)
    if not is_matched then
        date_part, time_part, sw_state, ev_level, module, msg_id, add_info, detail =
            msg:match("^(%d%d%d%d[/%-]%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        if matched(date_part) then is_matched = true; log_type = "EVENT" end
    end

    -- B2a: AX3660S 画面出力 (mm/dd, IF識別子あり, wwwあり)
    if not is_matched then
        date_part, time_part, sw_state, ev_level, module, if_id, msg_id, add_info, detail =
            msg:match("^(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+(PORT:[%w_/%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        if matched(date_part) then is_matched = true; log_type = "EVENT" end
    end

    -- B2b: AX3660S 画面出力 (mm/dd, IF識別子なし, wwwあり)
    if not is_matched then
        date_part, time_part, sw_state, ev_level, module, msg_id, add_info, detail =
            msg:match("^(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([0-9]+[SIMB])%s+([ER][0-9])%s+([%w_%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        if matched(date_part) then is_matched = true; log_type = "EVENT" end
    end

    -- B3: AX3630S 画面出力 (mm/dd, wwwなし)
    if not is_matched then
        date_part, time_part, ev_level, module, msg_id, add_info, detail =
            msg:match("^(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([ER][0-9])%s+([%w_%-]+)%s+([0-9a-fA-F]+)%s+([0-9a-fA-F]+:[0-9a-fA-F]+)%s+(.*)")
        if matched(date_part) then is_matched = true; log_type = "EVENT" end
    end

    -- -------------------------------------------------------------------------
    -- グループ C: 汎用 / 従来 / 簡易形式
    -- -------------------------------------------------------------------------

    -- C1: 汎用 yyyy/mm/dd 形式
    if not is_matched then
        log_type, date_part, time_part, ev_level, module, detail =
            msg:match("^([A-Z]+)%s+(%d%d%d%d[/%-]%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([EWIDR][0-9]*)%s+([%w_%-]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- C2: AX3660S / AX3630S メッセージテキスト形式 (RTM: / TRO: 等)
    --     例: EVT 08/22 12:00:00 RTM: BGP neighbor 10.0.0.1 Up
    if not is_matched then
        log_type, date_part, time_part, detail =
            msg:match("^([A-Z]+)%s+(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+(.*)")
        if matched(log_type) and detail and detail ~= "" then
            is_matched = true
            -- モジュール名はメッセージ先頭の "WORD:" から推測する
            local guessed = detail:match("^([%w_%-]+):")
            if guessed then module = guessed end
        end
    end

    -- C3: 従来 AX シリーズ形式 (mm/dd, SEVERITY + MODULE)
    --     例: LOG 08/22 11:00:00 I001 SYSTEM test legacy alaxala
    if not is_matched then
        log_type, date_part, time_part, ev_level, module, detail =
            msg:match("^([A-Z]+)%s+(%d%d[/%-]%d%d)%s+([0-9:.]+)%s+([EWIDR][0-9]*)%s+([%w_%-]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- C4: タイムスタンプなし簡易形式
    --     例: LOG E1 SYSTEM Power supply unit failure detected
    if not is_matched then
        log_type, ev_level, module, detail =
            msg:match("^([A-Z]+)%s+([EWIDR][0-9]*)%s+([%w_%-]+)%s+(.*)")
        is_matched = matched(log_type)
    end

    -- -------------------------------------------------------------------------
    -- 出力レコードの構築
    -- -------------------------------------------------------------------------
    if is_matched then
        if log_type  then out["log_type"]        = log_type       end
        if sw_state  then out["switch_state"]    = sw_state       end
        if if_id     then out["interface"]       = if_id          end
        if msg_id    then out["message_id"]      = msg_id         end
        if add_info  then out["additional_info"] = add_info       end

        if ev_level then
            out["severity"] = ev_level
            local sev = SEVERITY_MAP[ev_level]
                     or SEVERITY_MAP[ev_level:sub(1,1)]
                     or common.get_priority(ev_level)
            if sev then out["priority"] = sev end
        end

        if module then
            out["module"]  = module
            out["program"] = (ev_level and (ev_level .. " ") or "") .. module
        end

        out["message"]    = detail and common.trim(detail) or msg
        out["parse_type"] = "AlaxalA"

        -- タイムスタンプ解析
        local gen_ts = parse_alaxala_timestamp(date_part, time_part)
        return 1, (gen_ts or timestamp), out
    else
        out["parse_type"] = "AlaxalA_FALLBACK"
        return 1, timestamp, out
    end
end
