# Скрипт для обробки Excel файлів у Logstash
require 'roo'
require 'roo-xls'
require 'json'
require 'logger'

def register(params)
  @logger = Logger.new('/data/logs/excel_parser.log')
  @logger.info("Excel Parser initialized")
end

def filter(event)
  begin
    # Отримання шляху до файлу
    file_path = event.get('path')
    @logger.info("Processing Excel file: #{file_path}")
    
    # Створення тимчасового файлу
    temp_file = "/tmp/logstash_excel/#{File.basename(file_path)}"
    File.open(temp_file, 'wb') do |file|
      file.write(File.binread(file_path))
    end
    
    # Визначення типу Excel файлу
    extension = File.extname(file_path).downcase
    
    # Відкриття Excel файлу
    excel = case extension
            when '.xlsx'
              Roo::Excelx.new(temp_file)
            when '.xls'
              Roo::Excel.new(temp_file)
            else
              raise "Unsupported Excel format: #{extension}"
            end
    
    # Отримання першого листа
    sheet = excel.sheet(0)
    
    # Отримання заголовків (перший рядок)
    headers = sheet.row(1)
    
    # Обробка даних
    data = []
    (2..sheet.last_row).each do |i|
      row = sheet.row(i)
      row_data = {}
      
      headers.each_with_index do |header, index|
        row_data[header.to_s] = row[index]
      end
      
      data << row_data
    end
    
    # Додавання даних до події
    event.set('excel_data', data)
    
    # Додавання метаданих
    event.set('[@metadata][filename]', File.basename(file_path))
    event.set('[@metadata][sheet_count]', excel.sheets.length)
    event.set('[@metadata][row_count]', sheet.last_row - 1)
    
    # Видалення тимчасового файлу
    File.delete(temp_file) if File.exist?(temp_file)
    
    @logger.info("Successfully processed Excel file: #{file_path}, rows: #{sheet.last_row - 1}")
    
    # Повернення події
    return [event]
  rescue => e
    @logger.error("Error processing Excel file: #{e.message}")
    @logger.error(e.backtrace.join("\n"))
    
    # Створення події з помилкою
    event.set('excel_error', e.message)
    event.set('excel_error_backtrace', e.backtrace)
    event.tag('excel_parse_error')
    
    # Повернення події з помилкою
    return [event]
  end
end