import os
import sys
import requests
import subprocess
from pathlib import Path
from typing import Dict, List, Tuple

def check_sonarqube() -> Tuple[bool, str]:
    """Перевірка підключення до SonarQube"""
    try:
        token = 'ae5fe5168d12c610c7b94cdb641b53e1c54c0654'
        host = 'http://localhost:9000'
        project = 'predator-analytics'
        
        # Перевірка статусу сервера
        response = requests.get(
            f"{host}/api/system/status",
            auth=(token, ''),
            timeout=10,
            verify=True
        )
        
        if response.status_code != 200:
            return False, f"Помилка підключення до сервера: {response.status_code}"
            
        # Перевірка проекту
        project_response = requests.get(
            f"{host}/api/projects/search?projects={project}",
            auth=(token, ''),
            timeout=10
        )
        
        if project_response.status_code != 200:
            return False, "Помилка доступу до проекту"
        
        return True, "Підключення успішне"
        
    except requests.exceptions.SSLError:
        return False, "Помилка SSL сертифіката"
    except Exception as e:
        return False, str(e)

def check_tools() -> List[Dict]:
    """Перевірка наявності необхідних інструментів"""
    tools = {
        'sonar-scanner': 'sonar-scanner --version',
        'docker': 'docker --version',
        'python': 'python --version',
        'pip': 'pip --version',
        'git': 'git --version'
    }
    
    results = []
    for tool, command in tools.items():
        try:
            output = subprocess.check_output(command.split(), stderr=subprocess.STDOUT)
            results.append({
                'tool': tool,
                'status': True,
                'version': output.decode().strip()
            })
        except Exception:
            results.append({
                'tool': tool,
                'status': False,
                'version': None
            })
    return results

def check_configs() -> List[Dict]:
    """Перевірка конфігураційних файлів"""
    required_files = {
        'sonar-project.properties': 'SonarQube конфігурація',
        '.snyk': 'Snyk конфігурація',
        'docker-compose.yml': 'Docker конфігурація',
        '.github/workflows/ci.yml': 'GitHub Actions конфігурація',
        'requirements.txt': 'Python залежності'
    }
    
    results = []
    for file_path, description in required_files.items():
        file = Path(file_path)
        results.append({
            'file': file_path,
            'description': description,
            'exists': file.exists()
        })
    return results

def check_environment() -> List[Dict]:
    """Перевірка змінних середовища"""
    required_vars = {
        'SONAR_TOKEN': 'SonarQube токен',
        'GITHUB_TOKEN': 'GitHub токен',
        'SNYK_TOKEN': 'Snyk токен',
        'POSTGRES_HOST': 'PostgreSQL хост',
        'POSTGRES_PORT': 'PostgreSQL порт'
    }
    
    results = []
    for var, description in required_vars.items():
        value = os.getenv(var)
        results.append({
            'variable': var,
            'description': description,
            'exists': value is not None
        })
    return results

def main():
    print("🔍 Перевірка всіх підключень...\n")
    
    # Перевірка SonarQube
    sonar_ok, sonar_msg = check_sonarqube()
    print(f"{'✅' if sonar_ok else '❌'} SonarQube: {sonar_msg}")
    
    # Перевірка інструментів
    print("\nІнструменти:")
    for tool in check_tools():
        status = '✅' if tool['status'] else '❌'
        version = f" ({tool['version']})" if tool['version'] else ""
        print(f"{status} {tool['tool']}{version}")
    
    # Перевірка конфігураційних файлів
    print("\nКонфігураційні файли:")
    for config in check_configs():
        status = '✅' if config['exists'] else '❌'
        print(f"{status} {config['description']}")
    
    # Перевірка змінних середовища
    print("\nЗмінні середовища:")
    for var in check_environment():
        status = '✅' if var['exists'] else '❌'
        print(f"{status} {var['description']}")
    
    # Загальний результат
    all_checks = all([
        sonar_ok,
        all(t['status'] for t in check_tools()),
        all(c['exists'] for c in check_configs()),
        all(v['exists'] for v in check_environment())
    ])
    
    if all_checks:
        print("\n✅ Всі підключення та налаштування успішно перевірені!")
        sys.exit(0)
    else:
        print("\n❌ Знайдено проблеми з підключеннями!")
        sys.exit(1)

if __name__ == '__main__':
    main()
