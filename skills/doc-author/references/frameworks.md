# OpenAPI 匯出與補漏對照

## Contents
- 各框架匯出指令
- 補漏對照：完整度檢查發現缺漏時改哪裡

## 各框架匯出指令

能離線（不起服務）把 OpenAPI 匯出成檔案的，直接匯出；不能的，在 README 手寫
endpoint 表（見 SKILL.md Step 3）。

| 框架 | 匯出方式 |
|---|---|
| FastAPI / Starlette | 一行指令（module 路徑換成該 repo 的，例 `app.main`）：`python3 -c "import json; from app.main import app; print(json.dumps(app.openapi(), ensure_ascii=False, indent=2))" > openapi.json` |
| NestJS | bootstrap 加 `SwaggerModule.createDocument()` 後 `fs.writeFileSync('openapi.json', …)`，包成 `npm run gen:openapi`。這要動使用者的 bootstrap code，先徵求同意 |
| Spring Boot | `springdoc-openapi-maven-plugin`（build 期匯出，不必起服務） |
| Django + DRF | `drf-spectacular`：`python manage.py spectacular --file openapi.yaml` |
| Go | `swaggo/swag`：`swag init`（從註解產 `docs/swagger.json`） |
| 其他能產 OpenAPI 的 | 跑該框架的匯出器 |

判準：框架現狀就能匯出的直接匯。要新增依賴或改 code 才能匯出的
（例如 Express 從零接 swagger-jsdoc），先問使用者要不要接；不接就手寫
README 的功能一覽表。

## 補漏對照：完整度檢查發現缺漏時改哪裡

一律改 code 再重新匯出，不直接改 openapi.json（會被下次匯出蓋掉）。

| 缺漏 | FastAPI | 通則 |
|---|---|---|
| endpoint 沒描述 | route 的 `summary=`/`description=` 或 docstring | 該 operation 的標註 |
| 參數沒描述 | `Query(..., description=…)` / `Path(...)` | 該參數的標註 |
| 缺範例 | `responses={200:{"content":{...:{"example":…}}}}` 或 Pydantic `json_schema_extra` | schema 的 `example` |
| 缺錯誤宣告 | `responses` 補 4xx/5xx 與 schema | 宣告錯誤狀態碼與 schema |

「範例」的判定是字串層級（openapi.json 裡找 `example`/`examples` key，巢狀位置
都算），擋的是完全沒範例，不是範例品質。
