# 團隊名詞定義（glossary）

寫文件前先讀這份。文件裡用到表列名詞時，照這裡的定義與寫法（含大小寫、中英文選擇），
不另創講法——名詞不一致，跨專案的文件就搜不到、對不上。

維護方式：團隊共同維護，新增名詞直接加列。某一節太大要拆檔時，把該節搬到
`references/glossary/<主題>.md`，skill 會整個資料夾讀。

衝突處理：glossary 的定義優先於單一 repo 的慣用講法。repo 用法不同時，
文件照 glossary 寫，並註明 code 內的實際識別字。

## 檔案與文件慣例

| 名詞 | 定義 | 文件裡怎麼寫 |
|------|------|-------------|
| README.md | repo 門面，即使用文件：API 或工具怎麼用，規格表風格，單檔自足、可整份上傳文件平台 | 「README」或「使用文件」 |
| ARCHITECTURE.md | `docs/ARCHITECTURE.md`，架構文件：給維護者與 AI 的系統地圖（專案結構、分層、內建工具、設計說明） | 「架構文件」，路徑寫 `docs/ARCHITECTURE.md` |
| openapi.json | 從 code 匯出的 API 權威規格，不手改，改 code 重新匯出 | 「openapi.json」 |
| SOP | 業務操作程序文件，放 `docs/sops/<組名>/`，一檔一 API；由 PM 撰寫（sop-author 訪談產出） | 「SOP」 |
| spec | 由 SOP 轉出的實作規格，放 `docs/specs/<組名>/`（sop-to-spec 產出）；實作的唯一規格來源 | 「spec」或「規格」 |

## 通用技術名詞

| 名詞 | 定義 | 文件裡怎麼寫 |
|------|------|-------------|
| mock 模式 | 服務以記憶體模擬外部系統啟動（不連真實資料庫或第三方），用於測試與 demo；由 `MOCK_<系統>` 環境變數切換 | 「mock 模式」（不寫「模擬模式」「假資料模式」） |
| endpoint | 一個 `METHOD /path` 的 API 功能 | 「endpoint」（不寫「端點介面」） |

## 領域名詞

跨專案通用的業務名詞放這裡；單一專案專屬的寫在該 repo 的 ARCHITECTURE.md 即可。
格式如下（範例）：

| 名詞 | 定義 | 文件裡怎麼寫 |
|------|------|-------------|
| 回收筒 | Oracle `RECYCLEBIN`：被 DROP 的表在空間回收前的暫存區，期間可救回 | 「回收筒」，首次出現附 `RECYCLEBIN` |
