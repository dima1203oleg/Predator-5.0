import os
import sys
import requests
from pathlib import Path


def verify_sonar_setup():
    """Перевірка налаштувань SonarQube"""
    token = "ae5fe5168d12c610c7b94cdb641b53e1c54c0654"
    host = "http://localhost:9000"
    project = "predator-analytics"

    print("🔍 Перевірка налаштувань SonarQube...")

    try:
        # Перевірка з'єднання
        response = requests.get(
            f"{host}/api/system/status", auth=(token, ""), timeout=10, verify=True
        )

        if response.status_code != 200:
            print(f"❌ Помилка з'єднання: {response.status_code}")
            return False

        print("✅ З'єднання встановлено")

        # Перевірка проекту
        project_response = requests.get(
            f"{host}/api/projects/search?projects={project}", auth=(token, ""), timeout=10
        )

        if project_response.status_code == 200:
            projects = project_response.json().get("components", [])
            if any(p["key"] == project for p in projects):
                print(f"✅ Проект {project} існує")
            else:
                print(f"⚠️ Проект {project} не знайдено")
                return False
        else:
            print("❌ Помилка перевірки проекту")
            return False

        # Перевірка конфігурації
        if not Path("sonar-project.properties").exists():
            print("❌ Відсутній файл sonar-project.properties")
            return False

        print("✅ Конфігурація в порядку")
        return True

    except Exception as e:
        print(f"❌ Помилка: {str(e)}")
        return False


if __name__ == "__main__":
    if not verify_sonar_setup():
        sys.exit(1)
