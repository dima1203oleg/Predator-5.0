import os
import sys
import requests
from pathlib import Path
from requests.auth import HTTPBasicAuth

def verify_sonar_secrets():
    """Перевірка секретів та конфігурації SonarQube"""
    print("🔍 Перевірка налаштувань SonarQube...\n")
    
    # Перевірка змінних середовища
    host_url = os.getenv('SONAR_HOST_URL', 'http://localhost:9000')
    token = os.getenv('SONAR_TOKEN')

    if not token:
        print("❌ Помилка: змінна середовища SONAR_TOKEN не задана")
        return False
    
    # Перевірка конфігураційного файлу
    config_file = Path('sonar-project.properties')
    if not config_file.exists():
        print("❌ Відсутній файл sonar-project.properties")
        return False
        
    try:
        # Перевірка з'єднання
        response = requests.get(
            f"{host_url}/api/system/status",
            auth=HTTPBasicAuth(token, ''),
            timeout=10,
            verify=False  # Вимкнено перевірку SSL, якщо використовується самопідписаний сертифікат
        )
        
        if response.status_code != 200:
            print(f"❌ Помилка підключення до SonarQube: HTTP {response.status_code} - {response.text}")
            return False
        
        status = response.json()
        if 'status' in status and 'version' in status:
            print(f"✅ SonarQube доступний (версія {status.get('version')}, статус: {status.get('status')})")
        else:
            print("⚠️ Відповідь від SonarQube не містить необхідних полів (status/version)")
        
        # Перевірка проекту
        project_key = 'predator-analytics'
        project_response = requests.get(
            f"{host_url}/api/projects/search?projects={project_key}",
            auth=HTTPBasicAuth(token, ''),
            timeout=10
        )
        
        if project_response.status_code == 200:
            projects = project_response.json().get('components', [])
            if any(p['key'] == project_key for p in projects):
                print(f"✅ Проект {project_key} знайдено")
            else:
                print(f"⚠️ Проект {project_key} не знайдено")
        else:
            print(f"❌ Помилка отримання списку проєктів: HTTP {project_response.status_code} - {project_response.text}")
        
        return True
            
    except requests.exceptions.SSLError:
        print("❌ Помилка SSL сертифікату. Переконайтесь, що використовуєте дійсний сертифікат.")
        return False
    except requests.exceptions.ConnectionError:
        print("❌ Не вдалося підключитися до SonarQube. Переконайтесь, що сервер запущено та доступний.")
        return False
    except requests.exceptions.Timeout:
        print("❌ Час очікування відповіді від SonarQube вичерпано.")
        return False
    except Exception as e:
        print(f"❌ Неочікувана помилка перевірки: {str(e)}")
        return False

if __name__ == '__main__':
    if not verify_sonar_secrets():
        print("\n⚠️ Необхідні дії:")
        print("1. Перевірте підключення до SonarQube серверу")
        print("2. Переконайтеся, що змінна середовища SONAR_TOKEN задана")
        print("3. Перевірте файл sonar-project.properties")
        sys.exit(1)
    else:
        print("\n✅ Всі перевірки успішні")
