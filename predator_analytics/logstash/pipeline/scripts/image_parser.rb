# Скрипт для обробки зображень у Logstash з використанням OCR
require 'rtesseract'
require 'mini_magick'
require 'json'
require 'logger'

def register(params)
  @logger = Logger.new('/data/logs/image_parser.log')
  @logger.info("Image Parser initialized")
  
  # Параметри OCR
  @lang = params.fetch('lang', 'ukr+eng')
  @dpi = params.fetch('dpi', 300)
  @preprocess = params.fetch('preprocess', true)
  
  @logger.info("Image Parser configuration: lang=#{@lang}, dpi=#{@dpi}, preprocess=#{@preprocess}")
end

def filter(event)
  begin
    # Отримання шляху до файлу
    file_path = event.get('path')
    @logger.info("Processing image file: #{file_path}")
    
    # Створення тимчасового файлу
    temp_file = "/tmp/logstash_image/#{File.basename(file_path)}"
    File.open(temp_file, 'wb') do |file|
      file.write(File.binread(file_path))
    end
    
    # Попередня обробка зображення, якщо увімкнено
    if @preprocess
      preprocess_image(temp_file)
    end
    
    # Вилучення тексту з зображення за допомогою OCR
    text_content = extract_text_with_ocr(temp_file)
    
    # Додавання тексту до події
    event.set('image_text', text_content)
    
    # Додавання метаданих
    event.set('[@metadata][filename]', File.basename(file_path))
    event.set('[@metadata][text_length]', text_content.length)
    event.set('[@metadata][preprocessed]', @preprocess)
    
    # Видалення тимчасового файлу
    File.delete(temp_file) if File.exist?(temp_file)
    
    @logger.info("Successfully processed image file: #{file_path}, text length: #{text_content.length}")
    
    # Повернення події
    return [event]
  rescue => e
    @logger.error("Error processing image file: #{e.message}")
    @logger.error(e.backtrace.join("\n"))
    
    # Створення події з помилкою
    event.set('image_error', e.message)
    event.set('image_error_backtrace', e.backtrace)
    event.tag('image_parse_error')
    
    # Повернення події з помилкою
    return [event]
  end
end

def preprocess_image(file_path)
  begin
    # Використання MiniMagick для попередньої обробки зображення
    image = MiniMagick::Image.open(file_path)
    
    # Перетворення на чорно-біле зображення
    image.colorspace('gray')
    
    # Збільшення контрасту
    image.contrast
    
    # Видалення шуму
    image.enhance
    
    # Збільшення різкості
    image.sharpen
    
    # Збереження обробленого зображення
    image.write(file_path)
    
    @logger.info("Image preprocessing completed")
  rescue => e
    @logger.error("Error preprocessing image: #{e.message}")
  end
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