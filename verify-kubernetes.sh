#!/bin/bash

# Кольори для виводу
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логін і пароль
LOGIN="Dima1203"
PASSWORD="Emma0707@"

# Функція перевірки помилок
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Помилка виконання останньої команди${NC}"
    return 1
  else
    echo -e "${GREEN}✓ Команда виконана успішно${NC}"
    return 0
  fi
}

# Функція для заголовків
print_header() {
  echo -e "\n${BLUE}⸻${NC}"
  echo -e "${BLUE}🔹 $1${NC}"
  echo -e "${BLUE}⸻${NC}\n"
}

# Функція перевірки логіна та пароля
verify_credentials() {
  echo -e "${YELLOW}Перевірка логіна та пароля...${NC}"
  if [ "$LOGIN" != "Dima1203" ] || [ "$PASSWORD" != "Emma0707@" ]; then
    echo -e "${RED}⚠️ Невірний логін або пароль. Міняємо місцями...${NC}"
    TEMP=$LOGIN
    LOGIN=$PASSWORD
    PASSWORD=$TEMP
    echo -e "${YELLOW}Новий логін: $LOGIN, Новий пароль: $PASSWORD${NC}"
  else
    echo -e "${GREEN}Логін і пароль коректні${NC}"
  fi
}

verify_credentials

print_header "1. Перевірка стану Kubernetes"
echo "Виконую команду: kubectl cluster-info"
kubectl cluster-info
if check_error; then
  echo -e "${GREEN}✓ Kubernetes кластер працює коректно${NC}"
else
  echo -e "${RED}❌ Проблеми з доступом до Kubernetes кластера${NC}"
  echo "Перевірте, чи запущений кластер та чи налаштований kubectl"
fi

print_header "2. Перевірка статусу нод (вузлів)"
echo "Виконую команду: kubectl get nodes"
kubectl get nodes
if check_error; then
  NOT_READY_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status!="True")].metadata.name}')
  if [ -z "$NOT_READY_NODES" ]; then
    echo -e "${GREEN}✓ Всі вузли в статусі Ready${NC}"
  else
    echo -e "${RED}❌ Деякі вузли не в статусі Ready: $NOT_READY_NODES${NC}"
    for node in $NOT_READY_NODES; do
      echo "Перевірка логів проблемного вузла $node:"
      kubectl describe node $node | grep -A 5 "Conditions:"
    done
  fi
else
  echo -e "${RED}❌ Не вдалося отримати інформацію про вузли${NC}"
fi

print_header "3. Перевірка запущених подів"
echo "Виконую команду: kubectl get pods -A"
kubectl get pods -A
if check_error; then
  PROBLEM_PODS=$(kubectl get pods -A -o jsonpath='{range .items[?(@.status.phase!="Running" && @.status.phase!="Succeeded")]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.status.phase}{"\n"}{end}')
  if [ -з "$PROBLEM_PODS" ]; then
    echo -е "${GREEN}✓ Всі поди в статусі Running або Completed${NC}"
  else
    echo -е "${RED}❌ Виявлено проблемні поди:${NC}"
    echo "$PROBLEM_PODS" | while read namespace pod status; do
      if [ -н "$namespace" ] && [ -н "$pod" ]; then
        echo -е "Pod ${YELLOW}$pod${NC} в namespace ${YELLOW}$namespace${NC} має статус ${RED}$status${NC}"
        echo "Перевірка логів:"
        kubectl logs $pod -n $namespace --tail=20 2>/dev/null || echo "Не вдалося отримати логи."
        echo "Опис поду:"
        kubectl describe pod $pod -n $namespace | grep -E "Events:|Warning|Error" -A 5
        echo "------"
      fi
    done
  fi
else
  echo -е "${RED}❌ Не вдалося отримати інформацію про поди${NC}"
fi

print_header "4. Перевірка статусу сервісів"
echo "Виконую команду: kubectl get svc -A"
kubectl get svc -A
if check_error; then
  echo -е "${GREEN}✓ Сервіси налаштовані${NC}"
  echo "Перевірка сервісу my-application-service:"
  kubectl describe service my-application-service 2>/dev/null || echo "Сервіс my-application-service не знайдено"
else
  echo -е "${RED}❌ Не вдалося отримати інформацію про сервіси${NC}"
fi

print_header "5. Перевірка конфігурації Ingress"
echo "Виконую команду: kubectl get ingress -A"
kubectl get ingress -A
if check_error; then
  INGRESS_CONFIGURED=$(kubectl get ingress -A -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  if [ -н "$INGRESS_CONFIGURED" ]; then
    echo -е "${GREEN}✓ Ingress налаштований${NC}"
    echo "Перевірка ingress my-application-ingress:"
    kubectl describe ingress my-application-ingress 2>/dev/null || echo "Ingress my-application-ingress не знайдено"
    echo "Перевірка логів Ingress контролера:"
    kubectl logs -l app.kubernetes.io/name=ingress-nginx -n kube-system --tail=20 2>/dev/null || echo "Не вдалося знайти поди ingress-nginx в namespace kube-system"
  else
    echo -е "${YELLOW}⚠️ Ingress не налаштований${NC}"
  fi
else
  echo -е "${RED}❌ Не вдалося отримати інформацію про ingress${NC}"
fi

print_header "6. Перевірка підключення до PostgreSQL"
echo "Виконую команду: kubectl get pods -n database"
kubectl get pods -n database 2>/dev/null
if [ $? -eq 0 ]; then
  PG_POD=$(kubectl get pods -n database -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -н "$PG_POD" ]; then
    echo -е "${GREEN}✓ PostgreSQL под знайдено: $PG_POD${NC}"
    echo "Перевірка логів PostgreSQL:"
    kubectl logs $PG_POD -n database --tail=20 || echo "Не вдалося отримати логи PostgreSQL"
    echo "Перевірка стану PostgreSQL:"
    kubectl describe pod $PG_POD -n database | grep -E "Status:|Events:" -A 5
  else
    echo -е "${YELLOW}⚠️ PostgreSQL поди не знайдено в namespace database${NC}"
  fi
else
  echo -е "${YELLOW}⚠️ Namespace database не існує або немає прав доступу до нього${NC}"
fi

print_header "7. Перевірка статусу та логів контролерів"
echo "Виконую команду: kubectl get deployments -A"
kubectl get deployments -A
check_error

echo "Виконую команду: kubectl get daemonsets -A"
kubectl get daemonsets -A
check_error

echo "Виконую команду: kubectl get statefulsets -A"
kubectl get statefulsets -A
check_error

# Перевірка додатку my-application
echo -е "\nПеревірка логів додатку my-application:"
POD_NAME=$(kubectl get pods -l app=my-application -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
if [ -н "$POD_NAME" ]; then
  kubectl logs $POD_NAME --tail=20
  check_error
else
  echo -е "${RED}❌ Не вдалося знайти поди з міткою app=my-application${NC}"
fi

print_header "Перевірка доступу до додатку"
echo "Запуск port-forward для тестування:"
kubectl port-forward service/my-application-service 8080:80 &
PF_PID=$!
sleep 3
echo "Тестування HTTP-запиту:"
curl -s -m 5 http://localhost:8080 > /dev/null && echo -е "${GREEN}✓ HTTP-запит успішний${NC}" || echo -е "${RED}❌ Помилка HTTP-запиту${NC}"
kill $PF_PID 2>/dev/null

print_header "📌 Висновок"
# Підрахунок проблем
NODE_PROBLEMS=$(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status!="True")].metadata.name}' | wc -w)
POD_PROBLEMS=$(kubectl get pods -A -о jsonpath='{range .items[?(@.status.phase!="Running" && @.status.phase!="Succeeded")]}{.metadata.name}{"\n"}{end}' | wc -l)

if [ $NODE_PROBLEMS -eq 0 ] && [ $POD_PROBLEMS -eq 0 ]; then
  echo -е "${GREEN}✅ Kubernetes працює коректно. Всі вузли та поди в нормальному стані.${NC}"
else
  echo -е "${RED}⚠️ Виявлено проблеми в кластері Kubernetes:${NC}"
  [ $NODE_PROBLEMS -не 0 ] && echo -е "- Проблеми з ${RED}$NODE_PROBLEMS${NC} вузлами"
  [ $POD_PROBLEMS -не 0 ] && echo -е "- Проблеми з ${RED}$POD_PROBLEMS${NC} подами"
  echo -е "\nПерегляньте деталі вище для отримання додаткової інформації."
fi

echo -е "${GREEN}Перевірка завершена. 🚀${NC}"
