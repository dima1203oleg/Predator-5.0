import os


class Settings:
    POSTGRES_HOST: str = os.getenv("POSTGRES_HOST", "postgres_db")
    POSTGRES_DB: str = os.getenv("POSTGRES_DB", "predator_db")
    POSTGRES_USER: str = os.getenv("POSTGRES_USER", "admin")
    POSTGRES_PASSWORD: str = os.getenv("POSTGRES_PASSWORD", "password")
    POSTGRES_PORT: int = int(os.getenv("POSTGRES_PORT", "5432"))

    OPENSEARCH_HOSTS: list = [{"host": "opensearch", "port": 9200}]
    OLLAMA_HOST: str = os.getenv("OLLAMA_HOST", "ollama")
    H2O_HOST: str = os.getenv("H2O_HOST", "h2o")
    REDIS_HOST: str = os.getenv("REDIS_HOST", "redis")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", "6379"))


settings = Settings()
