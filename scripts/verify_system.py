import os
import sys
import requests
import yaml
import subprocess
from pathlib import Path
from typing import Tuple, Dict, List


def verify_sonarqube() -> Tuple[bool, str]:
    """Комплексна перевірка SonarQube"""
    try:
        host = os.getenv("SONAR_HOST_URL")
        token = os.getenv("SONAR_TOKEN")

        if not all([host, token]):
            return False, "Відсутні змінні SONAR_HOST_URL або SONAR_TOKEN"

        # Перевірка з'єднання з сервером
        response = requests.get(
            f"{host}/api/system/info", auth=(token, ""), timeout=10, verify=True
        )

        if response.status_code == 200:
            info = response.json()
            # Перевірка версії і статусу
            version = info.get("version", "unknown")
            status = info.get("status", "unknown")
            return True, f"SonarQube {version} ({status})"
        return False, f"Помилка з'єднання: {response.status_code}"
    except Exception as e:
        return False, f"Помилка: {str(e)}"


def verify_tools() -> List[Dict[str, bool]]:
    """Перевірка наявності необхідних інструментів"""
    tools = {
        "sonar-scanner": "sonar-scanner --version",
        "docker": "docker --version",
        "python": "python --version",
        "pip": "pip --version",
    }

    results = []
    for tool, command in tools.items():
        try:
            subprocess.check_output(command.split(), stderr=subprocess.STDOUT)
            results.append({"tool": tool, "installed": True})
        except:
            results.append({"tool": tool, "installed": False})
    return results


def verify_security_config() -> Tuple[bool, List[str]]:
    """Перевірка конфігурації безпеки"""
    errors = []

    # Перевірка файлів конфігурації
    required_files = {
        "sonar-project.properties": "SonarQube конфігурація",
        ".snyk": "Snyk конфігурація",
        ".github/workflows/ci.yml": "CI конфігурація",
        "Dockerfile": "Docker конфігурація",
    }

    for file_path, description in required_files.items():
        if not Path(file_path).exists():
            errors.append(f"Відсутній {description} ({file_path})")

    # Перевірка змінних середовища
    required_env = ["SONAR_TOKEN", "SNYK_TOKEN", "GITHUB_TOKEN"]
    missing_env = [var for var in required_env if not os.getenv(var)]
    if missing_env:
        errors.append(f"Відсутні змінні середовища: {', '.join(missing_env)}")

    return len(errors) == 0, errors


def main():
    print("🔍 Комплексна перевірка системи...\n")

    # Перевірка SonarQube
    sonar_ok, sonar_msg = verify_sonarqube()
    print(f"{'✅' if sonar_ok else '❌'} SonarQube: {sonar_msg}")

    # Перевірка інструментів
    print("\nПеревірка інструментів:")
    tools_status = verify_tools()
    for tool in tools_status:
        status = "✅" if tool["installed"] else "❌"
        print(f"{status} {tool['tool']}")

    # Перевірка конфігурації безпеки
    security_ok, security_errors = verify_security_config()
    print(f"\n{'✅' if security_ok else '❌'} Конфігурація безпеки:")
    if not security_ok:
        for error in security_errors:
            print(f"  - {error}")

    # Загальний результат
    success = all([sonar_ok, security_ok, all(tool["installed"] for tool in tools_status)])

    if success:
        print("\n✅ Всі перевірки успішні!")
        sys.exit(0)
    else:
        print("\n❌ Знайдено проблеми, що потребують вирішення")
        sys.exit(1)


if __name__ == "__main__":
    main()
