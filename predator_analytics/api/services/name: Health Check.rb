name: Health Check

on:
  schedule:
    - cron: '*/15 * * * *'  # Кожні 15 хвилин

jobs:
  health_check:
    runs-on: ubuntu-latest
    
    steps:
    - name: Check API health
      id: api_health
      uses: jtalk/url-health-check-action@v3
      with:
        url: http://${{ secrets.SERVER_HOST }}:8000/health
        max-attempts: 3
        retry-delay: 5s
        follow-redirect: true
      continue-on-error: true
    
    - name: Check OpenSearch health
      id: opensearch_health
      uses: jtalk/url-health-check-action@v3
      with:
        url: http://${{ secrets.SERVER_HOST }}:9200/_cluster/health
        max-attempts: 3
        retry-delay: 5s
        follow-redirect: true
      continue-on-error: true
    
    - name: Check Grafana health
      id: grafana_health
      uses: jtalk/url-health-check-action@v3
      with:
        url: http://${{ secrets.SERVER_HOST }}:3000/api/health
        max-attempts: 3
        retry-delay: 5s
        follow-redirect: true
      continue-on-error: true
    
    - name: Install SSH key
      if: steps.api_health.outcome == 'failure' || steps.opensearch_health.outcome == 'failure' || steps.grafana_health.outcome == 'failure'
      uses: shimataro/ssh-key-action@v2
      with:
        key: ${{ secrets.SSH_PRIVATE_KEY }}
        known_hosts: ${{ secrets.KNOWN_HOSTS }}
    
    - name: Restart failed services
      if: steps.api_health.outcome == 'failure' || steps.opensearch_health.outcome == 'failure' || steps.grafana_health.outcome == 'failure'
      env:
        SERVER_HOST: ${{ secrets.SERVER_HOST }}
        SERVER_USERNAME: ${{ secrets.SERVER_USERNAME }}
        DEPLOY_PATH: ${{ secrets.DEPLOY_PATH }}
      run: |
        ssh $SERVER_USERNAME@$SERVER_HOST << 'EOF'
          cd $DEPLOY_PATH
          
          # Перевірка та перезапуск API сервера
          if [ "${{ steps.api_health.outcome }}" == "failure" ]; then
            echo "API сервер не відповідає. Перезапуск..."
            docker-compose restart api_server
            sleep 10
          fi
          
          # Перевірка та перезапуск OpenSearch
          if [ "${{ steps.opensearch_health.outcome }}" == "failure" ]; then
            echo "OpenSearch не відповідає. Перезапуск..."
            docker-compose restart opensearch
            sleep 30
          fi
          
          # Перевірка та перезапуск Grafana
          if [ "${{ steps.grafana_health.outcome }}" == "failure" ]; then
            echo "Grafana не відповідає. Перезапуск..."
            docker-compose restart grafana
            sleep 10
          fi
          
          # Перевірка статусу контейнерів
          docker-compose ps
        EOF
    
    - name: Send notification about failure
      if: steps.api_health.outcome == 'failure' || steps.opensearch_health.outcome == 'failure' || steps.grafana_health.outcome == 'failure'
      uses: appleboy/telegram-action@master
      with:
        to: ${{ secrets.TELEGRAM_TO }}
        token: ${{ secrets.TELEGRAM_TOKEN }}
        message: |
          ⚠️ *Критична помилка в Predator Analytics 5.0!*

          Сервер: `${{ secrets.SERVER_HOST }}`
          
          Статус сервісів:
          - API: ${{ steps.api_health.outcome == 'success' && '✅ OK' || '❌ Не відповідає' }}
          - OpenSearch: ${{ steps.opensearch_health.outcome == 'success' && '✅ OK' || '❌ Не відповідає' }}
          - Grafana: ${{ steps.grafana_health.outcome == 'success' && '✅ OK' || '❌ Не відповідає' }}
          
          Було виконано автоматичний перезапуск проблемних сервісів.
          
          Посилання на workflow
    
    - name: Send notification about recovery
      if: steps.api_health.outcome == 'success' && steps.opensearch_health.outcome == 'success' && steps.grafana_health.outcome == 'success' && (github.event.workflow_run.conclusion == 'failure')
      uses: appleboy/telegram-action@master
      with:
        to: ${{ secrets.TELEGRAM_TO }}
        token: ${{ secrets.TELEGRAM_TOKEN }}
        message: |
          ✅ *Predator Analytics 5.0 відновлено!*
          
          Всі сервіси працюють нормально.
          Сервер: `${{ secrets.SERVER_HOST }}`
          Час відновлення: $(date +"%Y-%m-%d %H:%M:%S %Z")
          
          Посилання на workflow
