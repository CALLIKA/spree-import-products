# coding: utf-8
module ImportProducts
  module UserMailerExt
    def self.included(base)
      base.class_eval do
        def product_import_results(user, error_message = nil)
          @user = user
          @error_message = error_message
          attachments["import_products.log"] = File.read(IMPORT_PRODUCT_SETTINGS[:log_to]) if @error_message.nil?
          mail(:to => @user.email, :from => IMPORT_PRODUCT_SETTINGS[:mail_from], :subject => "Импорт продуктов: #{error_message.nil? ? "Успешно" : "Ошибка"}")
        end     
      end
    end
  end
end
