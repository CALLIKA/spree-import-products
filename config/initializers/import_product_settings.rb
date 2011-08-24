# coding: utf-8
# This file is the thing you have to config to match your application

IMPORT_PRODUCT_SETTINGS = {
  :unzip_folder_path => "#{Rails.root}/lib/etc/product_data/unzip_folder/",

  :column_mappings => { #Change these for manual mapping of product fields to the CSV file
    :sku => 0, 
    :name => 1,
    :master_price => 2,

    :cost_price => 3, 
    :weight => 4, 
    :height => 5,
    :width => 6,
    :depth => 7,

    :image_main => 8,
    :image_2 => 9,
    :image_3 => 10,
    :image_4 => 11,

    :description => 12,
    :category => 13
  },
  :create_missing_taxonomies => true,
  :log_to => File.join(Rails.root, '/log/', "import_products_#{Rails.env}.log"), #Where to log to
  :destroy_original_products => false, #Delete the products originally in the database after the import?
  :taxonomy_name => 'Тип товара',
  :mail_from => 'mailer@zoo61.ru'
}

