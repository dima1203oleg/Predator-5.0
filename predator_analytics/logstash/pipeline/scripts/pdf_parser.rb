# Скрипт для обробки PDF файлів у Logstash з використанням OCR
require 'pdf-reader'
require 'rtesseract'
require 'tempfile'
require 'json'
require 'logger'

def register(params)
  @logger = Logger.new('/data/logs/pdf_parser.log')
  @logger.info("PDF Parser initialized")
  
  # Параметри OCR
  @lang = params.fetch('lang', 'ukr+eng')
  @dpi = params.fetch('dpi', 300)
  @use_ocr = params.fetch('use_ocr', true)
  
  @logger.info("PDF Parser configuration: lang=#{@lang}, dpi=#{@dpi}, use_ocr=#{@use_ocr}")
end

def filter(event)
  begin
    # Отримання шляху до файлу
    file_path = event.get('path')
    @logger.info("Processing PDF file: #{file_path}")
    
    # Створення тимчасового файлу
    temp_file = "/tmp/logstash_pdf/#{File.basename(file_path)}"
    File.open(temp_file, 'wb') do |file|
      file.write(File.binread(file_path))
    end
    
    # Спроба вилучити текст безпосередньо з PDF
    text_content = extract_text_from_pdf(temp_file)
    
    # Якщо текст не вдалося вилучити і OCR увімкнено, використовуємо OCR
    if text_content.strip.empty? && @use_ocr
      @logger.info("No text found in PDF, using OCR")
      text_content = extract_text_with_ocr(temp_file)
    end
    
    # Додавання тексту до події
    event.set('pdf_text', text_content)
    
    # Додавання метаданих
    event.set('[@metadata][filename]', File.basename(file_path))
    event.set('[@metadata][text_length]', text_content.length)
    event.set('[@metadata][ocr_used]', text_content.strip.empty? && @use_ocr)
    
    # Видалення тимчасового файлу
    File.delete(temp_file) if File.exist?(temp_file)
    
    @logger.info("Successfully processed PDF file: #{file_path}, text length: #{text_content.length}")
    
    # Повернення події
    return [event]
  rescue => e
    @logger.error("Error processing PDF file: #{e.message}")
    @logger.error(e.backtrace.join("\n"))
    
    # Створення події з помилкою
    event.set('pdf_error', e.message)
    event.set('pdf_error_backtrace', e.backtrace)
    event.tag('pdf_parse_error')
    
    # Повернення події з помилкою
    return [event]
  end
end

def extract_text_from_pdf(file_path)
  text = ""
  begin
    reader = PDF::Reader.new(file_path)
    reader.pages.each do |page|
      text += page.text + "\n"
    end
  rescue => e
    @logger.warn("Error extracting text directly from PDF: #{e.message}")
  end
  return text
end

def extract_text_with_ocr(file_path)
  text = ""
  begin
    # Використання RTesseract для OCR
    text = RTesseract.new(file_path, lang: @lang, options: {dpi: @dpi}).to_s
  rescue => e
    @logger.error("Error extracting text with OCR: #{e.message}")
  end
  return text
end