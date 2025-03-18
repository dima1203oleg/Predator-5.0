# Скрипт для обробки Excel файлів у Logstash
require 'roo'
require 'roo-xls'
require 'json'
require 'logger'
require 'fileutils'

def register(params)
  @logger = Logger.new('/data/logs/excel_parser.log')
  @logger.info("Excel Parser initialized")
  @process_all_sheets = params.fetch('process_all_sheets', false)
end

def filter(event)
  begin
    # Отримання шляху до файлу
    file_path = event.get('path')
    @logger.info("Processing Excel file: #{file_path}")

    # Перевірка на порожній файл
    if File.zero?(file_path)
      @logger.warn("Skipping empty file: #{file_path}")
      event.tag('excel_empty_file')
      return [event]
    end

    # Створення тимчасового файлу
    temp_dir = "/tmp/logstash_excel"
    FileUtils.mkdir_p(temp_dir) unless File.directory?(temp_dir)
    temp_file = File.join(temp_dir, File.basename(file_path))
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

    # Обробка листів
    excel.sheets.each_with_index do |sheet_name, sheet_index|
      # Обробка тільки першого листа, якщо не вказано інше
      next if !@process_all_sheets && sheet_index > 0

      sheet = excel.sheet(sheet_name)

      # Перевірка на порожній лист
      if sheet.last_row < 2
        @logger.warn("Skipping empty sheet: #{sheet_name} in file: #{file_path}")
        event.tag('excel_empty_sheet')
        next
      end

      # Отримання заголовків (перший рядок)
      headers = sheet.row(1)

      # Обробка даних
      data = []
      (2..sheet.last_row).each do |i|
        row = sheet.row(i)
        row_data = {}

        headers.each_with_index do |header, index|
          begin
            cell_value = row[index]
            cell_type = sheet.celltype(i, index + 1)

            # Форматування значення в залежності від типу
            case cell_type
            when :float, :percentage
              cell_value = sheet.cell(i, index + 1).to_f
            when :date, :datetime
              cell_value = sheet.cell(i, index + 1).to_s
            when :string, :default
              cell_value = sheet.cell(i, index + 1).to_s
            else
              cell_value = sheet.cell(i, index + 1).to_s
            end

            row_data[header.to_s] = cell_value
          rescue => e
            @logger.error("Error processing cell in row #{i}, column #{index} in file #{file_path}: #{e.message}")
            row_data[header.to_s] = "ERROR: #{e.message}"
          end
        end

        data << row_data
      end

      # Додавання даних до події
      event.set("excel_data_#{sheet_name}", data)

      # Додавання метаданих
      event.set('[@metadata][filename]', File.basename(file_path))
      event.set('[@metadata][sheet_count]', excel.sheets.length)
      event.set('[@metadata][row_count_#{sheet_name}]', sheet.last_row - 1)
    end

    # Видалення тимчасового файлу
    FileUtils.rm_f(temp_file)

    @logger.info("Successfully processed Excel file: #{file_path}, sheets: #{excel.sheets.length}")

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
  ensure
    FileUtils.rm_f(temp_file) if File.exist?(temp_file)
  end
end
