from fastapi import HTTPException
from datetime import datetime, timedelta
import logging
import json
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from typing import List, Dict, Optional
from .auth_service import with_connection

logger = logging.getLogger(__name__)


@with_connection
async def create_visualization(
    conn,
    visualization_type: str,
    title: str,
    description: str,
    data_query: str,
    chart_config: dict,
    parameters: dict = None,
    created_by: str = None,
) -> int:
    """Створення нової візуалізації"""
    try:
        query = """
        INSERT INTO security_visualizations (
            visualization_type, title, description, 
            data_query, chart_config, parameters, created_by
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id
        """
        viz_id = await conn.fetchval(
            query,
            visualization_type,
            title,
            description,
            data_query,
            chart_config,
            parameters,
            created_by,
        )
        return viz_id
    except Exception as e:
        logger.error(f"Помилка при створенні візуалізації: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при створенні візуалізації")


@with_connection
async def generate_visualization(conn, viz_id: int, params: dict = None) -> dict:
    """Генерація візуалізації на основі збережених налаштувань"""
    try:
        # Отримуємо налаштування візуалізації
        viz_config = await conn.fetchrow(
            """
            SELECT visualization_type, data_query, chart_config, parameters
            FROM security_visualizations WHERE id = $1
        """,
            viz_id,
        )

        if not viz_config:
            raise HTTPException(status_code=404, detail="Візуалізацію не знайдено")

        # Виконуємо запит з параметрами
        query = viz_config["data_query"]
        data = await conn.fetch(query)

        # Конвертуємо дані в pandas DataFrame
        df = pd.DataFrame([dict(row) for row in data])

        # Створюємо візуалізацію за допомогою plotly
        fig = None
        chart_config = viz_config["chart_config"]

        if viz_config["visualization_type"] == "line":
            fig = px.line(df, **chart_config)
        elif viz_config["visualization_type"] == "bar":
            fig = px.bar(df, **chart_config)
        elif viz_config["visualization_type"] == "scatter":
            fig = px.scatter(df, **chart_config)
        elif viz_config["visualization_type"] == "pie":
            fig = px.pie(df, **chart_config)
        else:
            raise ValueError(
                f"Непідтримуваний тип візуалізації: {viz_config['visualization_type']}"
            )

        return {"plot_data": fig.to_json(), "data": df.to_dict(orient="records")}
    except Exception as e:
        logger.error(f"Помилка при генерації візуалізації: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при генерації візуалізації")


@with_connection
async def schedule_report(
    conn, report_type: str, schedule: dict, parameters: dict = None, created_by: str = None
) -> int:
    """Планування періодичного звіту"""
    try:
        query = """
        INSERT INTO report_schedules (
            report_type, schedule_config, parameters, created_by, next_run
        )
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
        """

        # Розраховуємо наступний запуск
        next_run = calculate_next_run(schedule)

        schedule_id = await conn.fetchval(
            query, report_type, schedule, parameters, created_by, next_run
        )

        return schedule_id
    except Exception as e:
        logger.error(f"Помилка при плануванні звіту: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при плануванні звіту")


def calculate_next_run(schedule: dict) -> datetime:
    """Розрахунок наступного часу запуску звіту"""
    now = datetime.utcnow()

    if schedule["frequency"] == "daily":
        next_run = now.replace(
            hour=schedule.get("hour", 0), minute=schedule.get("minute", 0), second=0
        )
        if next_run <= now:
            next_run += timedelta(days=1)
    elif schedule["frequency"] == "weekly":
        days_ahead = schedule["day"] - now.weekday()
        if days_ahead <= 0:
            days_ahead += 7
        next_run = now.replace(
            hour=schedule.get("hour", 0), minute=schedule.get("minute", 0), second=0
        ) + timedelta(days=days_ahead)
    elif schedule["frequency"] == "monthly":
        next_run = now.replace(
            day=schedule["day"],
            hour=schedule.get("hour", 0),
            minute=schedule.get("minute", 0),
            second=0,
        )
        if next_run <= now:
            if now.month == 12:
                next_run = next_run.replace(year=now.year + 1, month=1)
            else:
                next_run = next_run.replace(month=now.month + 1)

    return next_run


@with_connection
async def get_scheduled_reports(conn) -> List[dict]:
    """Отримання всіх запланованих звітів"""
    try:
        query = """
        SELECT id, report_type, schedule_config, parameters,
               created_by, created_at, next_run, last_run
        FROM report_schedules
        ORDER BY next_run ASC
        """
        schedules = await conn.fetch(query)
        return [dict(schedule) for schedule in schedules]
    except Exception as e:
        logger.error(f"Помилка при отриманні запланованих звітів: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні запланованих звітів")
