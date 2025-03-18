name: Deploy

on:
  workflow_run:
    workflows: ["Build and Push Docker Images"]
    types:
      - completed
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install SSH key
      uses: shimataro/ssh-key-action@v2
      with:
        key: ${{ secrets.SSH_PRIVATE_KEY }}
        known_hosts: ${{ secrets.KNOWN_HOSTS }}
    
    - name: Get Docker Image Versions
      id: get_image_versions
      run: |
        echo "API_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/${{ secrets.DOCKERHUB_USERNAME }}/predator-api/tags | jq -r '.results[0].name')" >> $GITHUB_OUTPUT
        echo "TELEGRAM_BOT_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/${{ secrets.DOCKERHUB_USERNAME }}/predator-telegram-bot/tags | jq -r '.results[0].name')" >> $GITHUB_OUTPUT
        echo "LOGSTASH_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/${{ secrets.DOCKERHUB_USERNAME }}/predator-logstash/tags | jq -r '.results[0].name')" >> $GITHUB_OUTPUT
    
    - name: Deploy to production server
      env:
        SERVER_HOST: ${{ secrets.SERVER_HOST }}
        SERVER_USERNAME: ${{ secrets.SERVER_USERNAME }}
        DEPLOY_PATH: ${{ secrets.DEPLOY_PATH }}
      run: |
        # Копіювання docker-compose.yml та .env файлів на сервер
        scp docker-compose.yml $SERVER_USERNAME@$SERVER_HOST:$DEPLOY_PATH/
        scp .env.example $SERVER_USERNAME@$SERVER_HOST:$DEPLOY_PATH/.env.example
        
        # Виконання команд на сервері
        ssh $SERVER_USERNAME@$SERVER_HOST << 'EOF'
          cd $DEPLOY_PATH
          
          # Створення .env файлу, якщо він не існує
          if [ ! -f .env ]; then
            cp .env.example .env
            echo "Створено новий .env файл з .env.example"
            echo "Будь ласка, оновіть значення в .env файлі!"
          fi
          
          # Перевірка на наявність змін
          if ! git diff --quiet HEAD; then
            echo "Зміни не виявлено. Розгортання пропущено."
            exit 0
          fi
          
          # Оновлення та перезапуск контейнерів
          docker-compose pull
          docker-compose up -d
          
          # Перевірка статусу контейнерів
          docker-compose ps
          
          # Перевірка на наявність помилок в логах
          docker-compose logs --tail 100 --no-color 2>&1 | grep -i "error\|fail\|exception"
          if [ $? -eq 0 ]; then
            echo "Виявлено помилки в логах!"
            exit 1
          fi
          
          # Очищення невикористовуваних образів
          docker image prune -f
        EOF
    
    - name: Send notification
      uses: appleboy/telegram-action@master
      with:
        to: ${{ secrets.TELEGRAM_TO }}
        token: ${{ secrets.TELEGRAM_TOKEN }}
        message: |
          🚀 Розгортання Predator Analytics 5.0 завершено успішно!
          
          Commit: ${{ github.event.workflow_run.head_commit.message }}
          Branch: ${{ github.event.workflow_run.head_branch }}
          Author: ${{ github.event.workflow_run.head_commit.author.name }}
          
          Сервер: ${{ secrets.SERVER_HOST }}
          
          Версії Docker образів:
          - API: ${{ steps.get_image_versions.outputs.API_VERSION }}
          - Telegram Bot: ${{ steps.get_image_versions.outputs.TELEGRAM_BOT_VERSION }}
          - Logstash: ${{ steps.get_image_versions.outputs.LOGSTASH_VERSION }}
