#! /usr/bin/python3

import requests
import csv
import base64
import time
import datetime
import glob
import os
from tqdm import tqdm

# OpenObserve から指定範囲のログをダウンロードする

# === 設定項目 ===
API_URL = "http://192.168.0.252:5080"
USERNAME = "root@root.root"
PASSWORD = "root"
STREAM_NAME = "syslog_ng"
ORG_ID = "default"
CHUNK_SIZE = 100000

# ログ取得範囲（日時指定）
START_TIME_STR = "2025-06-16 00:00:00"
END_TIME_STR   = "2025-06-16 23:59:59"
# ===============

def download_logs(api_url, username, password, stream_name, org_id="default", chunk_size=100000):
    credentials = f"{username}:{password}"
    encoded_credentials = base64.b64encode(credentials.encode()).decode()

    headers = {
        "Authorization": f"Basic {encoded_credentials}",
        "Content-Type": "application/json"
    }

    # 日時文字列をマイクロ秒に変換
    start_time_dt = datetime.datetime.strptime(START_TIME_STR, "%Y-%m-%d %H:%M:%S")
    end_time_dt   = datetime.datetime.strptime(END_TIME_STR, "%Y-%m-%d %H:%M:%S")
    start_time = int(start_time_dt.timestamp() * 1_000_000)
    end_time   = int(end_time_dt.timestamp() * 1_000_000)

    # 総件数を取得
    count_url = f"{api_url}/api/{org_id}/_search"
    count_payload = {
        "query": {
            "sql": f"SELECT COUNT(*) as total FROM {stream_name} WHERE _timestamp >= {start_time} AND _timestamp <= {end_time}",
            "start_time": start_time,
            "end_time": end_time
        },
        "search_type": "ui"
    }

    response = requests.post(count_url, json=count_payload, headers=headers)
    if response.status_code != 200:
        print(f"Failed to fetch total count: {response.status_code}, {response.text}")
        return

    total_logs = response.json().get("hits", [{}])[0].get("total", 0)
    print(f"Total logs to fetch: {total_logs}")

    last_timestamp = start_time
    file_index = 1
    current_fieldnames = set()
    total_fetched = 0
    temp_file = f"logs_temp_{file_index}.csv"

    # プログレスバーの初期化
    pbar = tqdm(total=total_logs, desc="Downloading logs", unit="logs")

    while total_fetched < total_logs:
        start_time_batch = time.time()

        url = f"{api_url}/api/{org_id}/_search"
        payload = {
            "query": {
                "sql": f"SELECT * FROM {stream_name} WHERE _timestamp > {last_timestamp} AND _timestamp <= {end_time} ORDER BY _timestamp ASC",
                "start_time": start_time,
                "end_time": end_time,
                "size": chunk_size
            },
            "search_type": "ui"
        }

        response = requests.post(url, json=payload, headers=headers)
        if response.status_code != 200:
            print(f"Failed to fetch logs: {response.status_code}, {response.text}")
            break

        logs = response.json().get("hits", [])
        if not logs:
            break

        # 新しいフィールドがあるか確認、あったらファイルを分割
        new_fields = set()
        for log in logs:
            new_fields.update(log.keys())

        if new_fields != current_fieldnames:
            current_fieldnames = new_fields
            file_index += 1
            temp_file = f"logs_temp_{file_index}.csv"
            with open(temp_file, "w", newline="") as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=sorted(current_fieldnames))
                writer.writeheader()
                writer.writerows(logs)
        else:
            with open(temp_file, "a", newline="") as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=sorted(current_fieldnames))
                writer.writerows(logs)

        last_timestamp = logs[-1]["_timestamp"]
        total_fetched += len(logs)
        
        # プログレスバーの更新
        pbar.update(len(logs))
        
        # 詳細情報の表示（プログレスバーの下に表示）
        last_timestamp_iso = datetime.datetime.fromtimestamp(last_timestamp / 1_000_000).isoformat()
        pbar.set_postfix({
            'last_timestamp': last_timestamp_iso,
            'batch_time': f'{time.time() - start_time_batch:.2f}s'
        })

        time.sleep(0.5)

    # プログレスバーを閉じる
    pbar.close()
    print("Download complete.")

# ダウンロードしたログを統合
def merge_csv_files():
    csv_files = sorted(glob.glob("logs_temp_*.csv"))
    merged_file = "logs_merged.csv"
    all_fieldnames = []

    print("Analyzing CSV files...")
    for file in csv_files:
        with open(file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for field in reader.fieldnames:
                if field not in all_fieldnames:
                    all_fieldnames.append(field)

    print(f"Merging {len(csv_files)} files...")
    with open(merged_file, "w", newline="", encoding="utf-8") as f_out:
        writer = csv.DictWriter(f_out, fieldnames=all_fieldnames)
        writer.writeheader()

        # ファイルマージ用のプログレスバー
        with tqdm(csv_files, desc="Merging files", unit="files") as pbar:
            for file in pbar:
                pbar.set_postfix({'current_file': file})
                with open(file, "r", encoding="utf-8") as f_in:
                    reader = csv.DictReader(f_in)
                    for row in reader:
                        writer.writerow(row)

    print(f"Merged into {merged_file}")

    # 一時ファイル削除
    print("Cleaning up temporary files...")
    for file in csv_files:
        try:
            os.remove(file)
            print(f"Deleted: {file}")
        except Exception as e:
            print(f"Failed to delete {file}: {e}")

def main():
    download_logs(API_URL, USERNAME, PASSWORD, STREAM_NAME, ORG_ID, CHUNK_SIZE)
    merge_csv_files()

if __name__ == "__main__":
    main()

