import os
import httpx
import aiohttp
import asyncpg
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from typing import Optional, List
from api.routes import auth, data, analytics
from api.config import settings
import logging

# Налаштування логування
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Налаштування авторизації
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

app = FastAPI(title="Predator Analytics 5.0 API Server")


# Моделі даних
class QueryRequest(BaseModel):
    query: str
    data_source: str = "auto"  # auto, postgres, opensearch, ollama, h2o


class Token(BaseModel):
    access_token: str
    token_type: str


# Класифікація запитів
def classify_query(query: str) -> str:
    lower_query = query.lower()
    if "select" in lower_query or "from" in lower_query:
        return "postgres"
    elif any(word in lower_query for word in ["пошук", "знайди"]):
        return "opensearch"
    elif any(word in lower_query for word in ["аналіз", "прогноз"]):
        return "ollama"
    elif "кластеризація" in lower_query:
        return "h2o"
    return "unknown"


# Пул з'єднань PostgreSQL
db_pool: asyncpg.pool.Pool = None


@app.on_event("startup")
async def startup():
    global db_pool
    db_pool = await asyncpg.create_pool(
        host=settings.POSTGRES_HOST,
        database=settings.POSTGRES_DB,
        user=settings.POSTGRES_USER,
        password=settings.POSTGRES_PASSWORD,
        port=settings.POSTGRES_PORT,
    )


@app.on_event("shutdown")
async def shutdown():
    await db_pool.close()


async def get_db_connection():
    async with db_pool.acquire() as conn:
        yield conn


# Обробка SQL-запитів
async def handle_sql(query: str, conn: asyncpg.Connection = Depends(get_db_connection)):
    try:
        result = await conn.fetch(query)
        return [dict(record) for record in result]
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# Маршрути
app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(data.router, prefix="/data", tags=["data"])
app.include_router(analytics.router, prefix="/analytics", tags=["analytics"])


@app.get("/")
async def read_root():
    return {"message": "Welcome to Predator Analytics 5.0"}


@app.post("/query/", dependencies=[Depends(oauth2_scheme)])
async def process_query(request: QueryRequest):
    query = request.query
    data_source = request.data_source.lower()

    try:
        if data_source == "auto":
            data_source = classify_query(query)
            if data_source == "unknown":
                raise HTTPException(status_code=400, detail="Неможливо визначити тип запиту")

        if data_source == "postgres":
            return await handle_sql(query)
        elif data_source == "opensearch":
            async with httpx.AsyncClient() as client:
                payload = {"query": {"match": {"_all": query}}}
                response = await client.post(
                    f"{settings.OPENSEARCH_HOSTS[0]['host']}:9200/customs_data/_search",
                    json=payload,
                )
                response.raise_for_status()
                return response.json()
        elif data_source == "ollama":
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{settings.OLLAMA_HOST}:11434/api/generate", json={"prompt": query}
                ) as resp:
                    return await resp.json()
        elif data_source == "h2o":
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{settings.H2O_HOST}:54321/cluster",
                    json={"data": query, "algorithm": "default"},
                ) as resp:
                    return await resp.json()
        else:
            raise HTTPException(status_code=400, detail="Невідоме джерело даних")
    except Exception as e:
        logger.error(f"Помилка обробки запиту: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/metrics")
async def metrics():
    return {
        "api_requests_total": 100,  # Реальний збір метрик потребує інтеграції з Prometheus
        "api_response_time_avg": 0.2,
        "errors_total": 0,
    }
