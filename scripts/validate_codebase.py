import os
import sys
import subprocess
import re
import json
from pathlib import Path
from typing import List, Dict, Any, Tuple

def check_python_syntax(directory: Path) -> List[Dict[str, Any]]:
    """Перевірка синтаксису Python файлів"""
    errors = []
    
    for file_path in directory.rglob("*.py"):
        relative_path = file_path.relative_to(directory)
        result = subprocess.run(
            ["python", "-m", "py_compile", str(file_path)],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            errors.append({
                "file": str(relative_path),
                "error_type": "syntax",
                "message": result.stderr.strip()
            })
    
    return errors

def check_sql_syntax(directory: Path) -> List[Dict[str, Any]]:
    """Базова перевірка синтаксису SQL файлів"""
    errors = []
    
    for file_path in directory.rglob("*.sql"):
        relative_path = file_path.relative_to(directory)
        
        with open(file_path, "r") as f:
            content = f.read()
            
            # Перевірка балансу дужок
            if content.count('(') != content.count(')'):
                errors.append({
                    "file": str(relative_path),
                    "error_type": "syntax",
                    "message": "Незбалансовані дужки в SQL файлі"
                })
                
            # Перевірка незакритих лапок
            if content.count("'") % 2 != 0:
                errors.append({
                    "file": str(relative_path),
                    "error_type": "syntax",
                    "message": "Незакриті одиночні лапки в SQL файлі"
                })
                
            # Перевірка відсутності крапки з комою в кінці запитів
            sql_statements = re.split(r';(?!\s*--)', content)
            for statement in sql_statements:
                if statement.strip() and not statement.strip().endswith(';') and not re.match(r'^\s*--', statement):
                    errors.append({
                        "file": str(relative_path),
                        "error_type": "style",
                        "message": "SQL запит без крапки з комою"
                    })
    
    return errors

def check_circular_imports(directory: Path) -> List[Dict[str, Any]]:
    """Перевірка на циклічні імпорти"""
    import_map = {}
    errors = []
    
    for file_path in directory.rglob("*.py"):
        relative_path = str(file_path.relative_to(directory))
        module_name = relative_path.replace("/", ".").replace(".py", "")
        
        with open(file_path, "r") as f:
            content = f.readlines()
            imports = []
            
            for line in content:
                if line.startswith("from ") and " import " in line:
                    module = line.split("from ")[1].split(" import ")[0].strip()
                    imports.append(module)
                elif line.startswith("import "):
                    modules = line[7:].split(",")
                    imports.extend([m.strip() for m in modules])
            
            import_map[module_name] = imports
    
    visited = set()
    path = []
    
    def check_cycle(module):
        if module in path:
            cycle_start = path.index(module)
            cycle = path[cycle_start:] + [module]
            errors.append({
                "error_type": "circular_import",
                "message": f"Циклічний імпорт: {' -> '.join(cycle)}"
            })
            return
            
        if module in visited or module not in import_map:
            return
            
        visited.add(module)
        path.append(module)
        
        for imported in import_map.get(module, []):
            check_cycle(imported)
            
        path.pop()
    
    for module in import_map:
        check_cycle(module)
    
    return errors

def check_security_issues(directory: Path) -> List[Dict[str, Any]]:
    """Перевірка базових проблем безпеки"""
    errors = []
    
    for file_path in directory.rglob("*.py"):
        relative_path = file_path.relative_to(directory)
        
        with open(file_path, "r") as f:
            content = f.read()
            
            # Перевірка на захардкоджені секрети
            secret_patterns = [
                (r'SECRET_KEY\s*=\s*[\'"][^\'"]+[\'"]', "Захардкоджений SECRET_KEY"),
                (r'password\s*=\s*[\'"][^\'"]+[\'"]', "Захардкоджений пароль"),
                (r'token\s*=\s*[\'"][a-zA-Z0-9]{20,}[\'"]', "Можливий захардкоджений токен"),
                (r'api[_-]?key\s*=\s*[\'"][^\'"]+[\'"]', "Захардкоджений API ключ")
            ]
            
            for pattern, message in secret_patterns:
                matches = re.finditer(pattern, content, re.IGNORECASE)
                for match in matches:
                    # Виключаємо випадки, коли це частина os.getenv() або подібного
                    if not re.search(r'os\.getenv|os\.environ', match.string[max(0, match.start()-50):match.start()]):
                        errors.append({
                            "file": str(relative_path),
                            "error_type": "security",
                            "message": message,
                            "line": content[:match.start()].count('\n') + 1
                        })
            
            # Перевірка на SQL ін'єкції
            sql_patterns = [
                (r'execute\([^,)]*\s\+\s', "Можлива SQL ін'єкція: конкатенація рядків у SQL запиті"),
                (r'f"[^"]*SELECT[^"]*{[^}]+}', "Можлива SQL ін'єкція: використання f-string з SQL"),
                (r"f'[^']*SELECT[^']*{[^}]+}", "Можлива SQL ін'єкція: використання f-string з SQL")
            ]
            
            for pattern, message in sql_patterns:
                matches = re.finditer(pattern, content)
                for match in matches:
                    errors.append({
                        "file": str(relative_path),
                        "error_type": "security",
                        "message": message,
                        "line": content[:match.start()].count('\n') + 1
                    })
            
            # Перевірка на проблеми з верифікацією SSL
            ssl_patterns = [
                (r'verify\s*=\s*False', "Відключена верифікація SSL"),
            ]
            
            for pattern, message in ssl_patterns:
                matches = re.finditer(pattern, content)
                for match in matches:
                    errors.append({
                        "file": str(relative_path),
                        "error_type": "security",
                        "message": message,
                        "line": content[:match.start()].count('\n') + 1
                    })
    
    return errors

def check_docker_config(directory: Path) -> List[Dict[str, Any]]:
    """Перевірка конфігурацій Docker"""
    errors = []
    
    dockerfile = directory / "Dockerfile"
    if dockerfile.exists():
        with open(dockerfile, "r") as f:
            content = f.read()
            
            # Перевірка наявності USER інструкції
            if not re.search(r'^USER\s+\S+', content, re.MULTILINE):
                errors.append({
                    "file": "Dockerfile",
                    "error_type": "security",
                    "message": "Відсутня інструкція USER у Dockerfile (запуск контейнера від root)"
                })
            
            # Перевірка використання останньої версії образу
            if re.search(r'FROM\s+\S+:latest', content):
                errors.append({
                    "file": "Dockerfile",
                    "error_type": "best_practice",
                    "message": "Використання тегу latest у базовому образі"
                })
    
    compose_file = directory / "docker-compose.yml"
    if compose_file.exists():
        with open(compose_file, "r") as f:
            content = f.read()
            
            # Перевірка захардкоджених секретів
            if re.search(r'password:', content) and not re.search(r'\${[^}]+}', content):
                errors.append({
                    "file": "docker-compose.yml",
                    "error_type": "security",
                    "message": "Можливі захардкоджені паролі в docker-compose.yml"
                })
    
    return errors

def check_ci_cd_config(directory: Path) -> List[Dict[str, Any]]:
    """Перевірка налаштувань CI/CD"""
    errors = []
    
    github_actions = directory / ".github" / "workflows"
    if github_actions.exists():
        for workflow_file in github_actions.glob("*.yml"):
            with open(workflow_file, "r") as f:
                try:
                    content = f.read()
                    
                    # Перевірка на використання фіксованих версій дій
                    if re.search(r'uses:\s+\S+@master', content):
                        errors.append({
                            "file": f".github/workflows/{workflow_file.name}",
                            "error_type": "best_practice",
                            "message": "Використання master/main замість конкретної версії дії"
                        })
                    
                    # Перевірка на використання секретів
                    secrets_in_file = re.findall(r'\$\{\{\s*secrets\.([^}]+)\s*\}\}', content)
                    for secret in secrets_in_file:
                        if secret.lower() in ["token", "password", "key"]:
                            errors.append({
                                "file": f".github/workflows/{workflow_file.name}",
                                "error_type": "best_practice",
                                "message": f"Використовується загальна назва секрету: {secret}"
                            })
                except Exception as e:
                    errors.append({
                        "file": f".github/workflows/{workflow_file.name}",
                        "error_type": "parse_error",
                        "message": f"Помилка при аналізі файлу: {str(e)}"
                    })
    
    return errors

def check_dependencies(directory: Path) -> List[Dict[str, Any]]:
    """Перевірка залежностей на версії та конфлікти"""
    errors = []
    
    requirements_file = directory / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, "r") as f:
            lines = f.readlines()
            
            for line in lines:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                    
                # Перевірка заморожених версій
                if "==" in line and not ("<" in line or ">" in line):
                    package, version = line.split("==")
                    errors.append({
                        "file": "requirements.txt",
                        "error_type": "best_practice",
                        "message": f"Заморожена версія пакету {package}=={version}"
                    })
    
    return errors

def analyze_pylint(directory: Path) -> List[Dict[str, Any]]:
    """Запуск pylint для перевірки коду"""
    errors = []
    
    try:
        result = subprocess.run(
            ["pylint", "--output-format=json", str(directory / "predator_analytics")],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            try:
                pylint_errors = json.loads(result.stdout)
                for error in pylint_errors:
                    if error["type"] in ["error", "warning"]:
                        errors.append({
                            "file": error["path"],
                            "error_type": "pylint",
                            "message": error["message"],
                            "line": error["line"]
                        })
            except json.JSONDecodeError:
                pass
    except FileNotFoundError:
        errors.append({
            "file": None,
            "error_type": "environment",
            "message": "pylint не встановлено"
        })
    
    return errors

def run_tests(directory: Path) -> Tuple[bool, str]:
    """Запуск тестів"""
    try:
        result = subprocess.run(
            ["pytest", "--maxfail=3", "--disable-warnings", "--tb=short", "--cov=."],
            cwd=directory,
            capture_output=True,
            text=True
        )
        
        return result.returncode == 0, result.stdout
    except FileNotFoundError:
        return False, "pytest не встановлено"

def main():
    current_dir = Path.cwd()
    print(f"🔍 Перевірка коду в {current_dir}...\n")
    
    all_errors = []
    
    print("Перевірка синтаксису Python...")
    all_errors.extend(check_python_syntax(current_dir))
    
    print("Перевірка SQL синтаксису...")
    all_errors.extend(check_sql_syntax(current_dir))
    
    print("Перевірка циклічних імпортів...")
    all_errors.extend(check_circular_imports(current_dir))
    
    print("Перевірка проблем безпеки...")
    all_errors.extend(check_security_issues(current_dir))
    
    print("Перевірка Docker конфігурацій...")
    all_errors.extend(check_docker_config(current_dir))
    
    print("Перевірка CI/CD налаштувань...")
    all_errors.extend(check_ci_cd_config(current_dir))
    
    print("Перевірка залежностей...")
    all_errors.extend(check_dependencies(current_dir))
    
    if not all_errors:
        print("\n✅ Код успішно пройшов всі перевірки!")
    else:
        print(f"\n❌ Знайдено {len(all_errors)} проблем у коді:")
        
        # Групування помилок за файлами
        errors_by_file = {}
        for error in all_errors:
            file_path = error.get("file", "Загальні помилки")
            if file_path not in errors_by_file:
                errors_by_file[file_path] = []
            errors_by_file[file_path].append(error)
        
        for file_path, errors in errors_by_file.items():
            print(f"\n📄 {file_path}:")
            for error in errors:
                line = f"рядок {error.get('line', '?')}: " if error.get('line') else ""
                print(f"  - {error['error_type']}: {line}{error['message']}")
    
    print("\n🧪 Запуск тестів...")
    success, output = run_tests(current_dir)
    if success:
        print("✅ Всі тести успішні!")
    else:
        print("❌ Тести не пройшли:")
        print(output)

if __name__ == "__main__":
    main()
