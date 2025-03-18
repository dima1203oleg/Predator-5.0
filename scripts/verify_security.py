import os
import sys
import requests
import yaml
from pathlib import Path
from typing import Tuple, List


def verify_sonarqube() -> Tuple[bool, str]:
    """Перевірка налаштувань SonarQube"""
    try:
        host = os.getenv("SONAR_HOST_URL")
        token = os.getenv("SONAR_TOKEN")
        project_key = "predator-analytics"

        if not all([host, token]):
            return False, "Відсутні змінні SONAR_HOST_URL або SONAR_TOKEN"

        # Перевірка підключення
        response = requests.get(
            f"{host}/api/system/info",
            auth=(token, ""),
            timeout=10,
            verify=True,  # Додаємо SSL верифікацію
        )

        if response.status_code != 200:
            return False, f"Помилка підключення: {response.status_code}"

        # Перевірка налаштувань проекту
        project_response = requests.get(
            f"{host}/api/projects/search?projects={project_key}", auth=(token, ""), timeout=10
        )

        if project_response.status_code != 200:
            return False, "Помилка перевірки проекту"

        # Перевірка Quality Gate
        gate_response = requests.get(
            f"{host}/api/qualitygates/get_by_project?project={project_key}",
            auth=(token, ""),
            timeout=10,
        )

        if gate_response.status_code != 200:
            return False, "Quality Gate не налаштовано"

        return True, "SonarQube налаштовано коректно"

    except Exception as e:
        return False, f"Помилка: {str(e)}"


def verify_snyk() -> Tuple[bool, List[str]]:
    """Перевірка налаштувань Snyk"""
    errors = []

    # Перевірка токену
    if not os.getenv("SNYK_TOKEN"):
        errors.append("Відсутній SNYK_TOKEN")

    # Перевірка конфігурації
    snyk_file = Path(".snyk")
    if not snyk_file.exists():
        errors.append("Відсутній файл .snyk")
    else:
        try:
            with open(snyk_file) as f:
                config = yaml.safe_load(f)
                if not config.get("version"):
                    errors.append("Некоректний формат .snyk")
                if not config.get("severity-threshold"):
                    errors.append("Не налаштований поріг критичності")
        except Exception as e:
            errors.append(f"Помилка читання .snyk: {str(e)}")

    return len(errors) == 0, errors


def verify_github_actions():
    """Перевірка налаштувань GitHub Actions"""
    workflow_dir = Path(".github/workflows")
    if not workflow_dir.exists():
        print("❌ Відсутня директорія .github/workflows")
        return False

    required_files = {"ci.yml", "deploy.yml"}
    existing_files = {f.name for f in workflow_dir.glob("*.yml")}

    missing = required_files - existing_files
    if missing:
        print(f"❌ Відсутні файли: {missing}")
        return False

    print("✅ GitHub Actions налаштування коректні")
    return True


def main():
    print("🔍 Комплексна перевірка безпеки...\n")

    # Перевірка SonarQube
    sonar_success, sonar_message = verify_sonarqube()
    print(f"{'✅' if sonar_success else '❌'} SonarQube: {sonar_message}")

    # Перевірка Snyk
    snyk_success, snyk_errors = verify_snyk()
    print(f"{'✅' if snyk_success else '❌'} Snyk:")
    if not snyk_success:
        for error in snyk_errors:
            print(f"  - {error}")

    # Загальний результат
    if not all([sonar_success, snyk_success]):
        print("\n❌ Знайдено проблеми в налаштуваннях безпеки")
        sys.exit(1)
    else:
        print("\n✅ Всі перевірки безпеки успішні")


if __name__ == "__main__":
    main()
