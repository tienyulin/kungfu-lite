# OpenAPI 匯出（各框架）與補漏對照

## Contents
- 各框架匯出指令（Mode A 判定表）
- 補漏對照：完整度檢查發現缺漏改哪裡

## 各框架匯出指令

能「離線/build 時把 OpenAPI 匯出成檔」→ Mode A；不能 → Mode B。

| 框架 | 匯出方式 |
|---|---|
| **FastAPI / Starlette** | 一行指令（module 路徑換成該 repo 的，例 `app.main`）：`python3 -c "import json; from app.main import app; print(json.dumps(app.openapi(), ensure_ascii=False, indent=2))" > openapi.json` |
| **NestJS**（TS） | bootstrap 加 `SwaggerModule.createDocument()` → `fs.writeFileSync('openapi.json', …)`，包成 `npm run gen:openapi`。**這是一段工程工作**：要動 user 的 bootstrap code，先徵求同意再改 |
| **Spring Boot** | `springdoc-openapi-maven-plugin`（build 期匯出，不必起服務） |
| **Django + DRF** | `drf-spectacular`：`python manage.py spectacular --file openapi.yaml`（純離線） |
| **Go** | `swaggo/swag`：`swag init`（從註解產 `docs/swagger.json`） |
| 其他能產 OpenAPI 的 | 跑該框架的匯出器產出 spec 檔 |

判準補充：框架**現狀**就能匯出 → Mode A。要新增依賴或改 code 才能匯出（例
Express + swagger-jsdoc 從零接）→ 先問使用者要不要接；不接就走 Mode B（在
README 手寫功能一覽表，五分鐘完事）。

## 補漏對照：完整度檢查發現缺漏改哪裡

一律改 code 再重匯，不直接改 openapi.json（會被下次重匯蓋掉）。

| 缺漏 | FastAPI | 通則 |
|---|---|---|
| endpoint 沒描述 | route `summary=`/`description=` 或 docstring | 該 operation 的標註 |
| 參數沒描述 | `Query(..., description=…)` / `Path(...)` | 該參數的標註 |
| 缺範例 | `responses={200:{"content":{...:{"example":…}}}}` 或 Pydantic `json_schema_extra` | schema 的 `example` |
| 缺 error | `responses` 補 4xx/5xx + schema | 宣告 error 狀態碼 + schema |

注意：「範例」的判定是字串層級（openapi.json 裡找 `example`/`examples` key），
巢狀位置都算；擋的是「完全沒範例」，不是範例品質。
