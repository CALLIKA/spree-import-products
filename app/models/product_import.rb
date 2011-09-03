# coding: utf-8
# This model is the master routine for uploading products
# Requires Paperclip and CSV to upload the CSV file and read it nicely.

# Original Author:: Josh McArthur
# Author:: Chetan Mittal
# License:: MIT

class ProductImport < ActiveRecord::Base
  has_attached_file :data_file, :path => ":rails_root/lib/etc/product_data/data-files/:basename.:extension"
  validates_attachment_presence :data_file

  require 'rubygems'
  require 'zip/zip'
  require 'nokogiri'
  require 'fileutils'

  require 'pp'
  require 'open-uri'

  ## Data Importing:
  # List Price maps to Master Price, Current MAP to Cost Price, Net 30 Cost unused
  # Width, height, Depth all map directly to object
  # Image main is created independtly, then each other image also created and associated with the product
  # Meta keywords and description are created on the product model

  def import_data!
      log("Import Start\n")
      # extract
      unzip_file(self.data_file.path, IMPORT_PRODUCT_SETTINGS[:unzip_folder_path])
      f_name = File.basename(self.data_file.path, ".zip")
      path_to_xml = "#{IMPORT_PRODUCT_SETTINGS[:unzip_folder_path]}#{f_name}/import.xml"
      log("Path to XML file: #{path_to_xml}\n")
      if File.exist?(path_to_xml) && File.readable?(path_to_xml)
	begin
	  log("File exists and readable\n")
          doc = Nokogiri::XML(File.open(path_to_xml))	

	  taxonomy = doc.xpath("//Классификатор")
	  groups_source = taxonomy.xpath("Группы")
	  @groups = {}
	  add_groups_recourse(groups_source, nil, @groups)
	  taxonomy_import(@groups)
	  #log(@groups)

	  doc.xpath("//Каталог/Товары/Товар").each do |product|
	    product_information = {}
	    product_information[:sku] = product.xpath("Ид").text
	    product_information[:name] = product.xpath("Наименование").text
	    product_information[:master_price] = 0
	    product_information[:description] = product.xpath("ПолноеНаименование").text
	    product_information[:available_on] = DateTime.now - 1.day# if product_information[:available_on].nil?
	    product_information[:images] = []
	    product_information[:taxonomy] = []

	    product.xpath("Группы/Ид").each do |product_group|
	    	product_information[:taxonomy] << product_group.text
	    end

	    product.xpath("Картинка").each do |image|
		#log("#{IMPORT_PRODUCT_SETTINGS[:unzip_folder_path]}#{f_name}/#{image.text}")
	    	product_information[:images] << "#{IMPORT_PRODUCT_SETTINGS[:unzip_folder_path]}#{f_name}/#{image.text}"
	    end

	    next unless create_product_using(product_information)
	  end
	rescue => error
		log(error, :error)
	end
      end

      begin
        File.delete(self.data_file.path)
	FileUtils.rm_rf("#{IMPORT_PRODUCT_SETTINGS[:unzip_folder_path]}#{f_name}")
      rescue => error
	log("Can not remove source archive and unarchived folder [#{error}]",:error)
      end	

    #All done!
    return [:notice, "Product data was successfully imported."]
  end


  private

  # source should be a zip file.
  # target should be a directory to output the contents to.
  def unzip_file (file, destination)
    Zip::ZipFile.open(file) { |zip_file|
     zip_file.each { |f|
       f_path=File.join(destination, f.name)
       FileUtils.mkdir_p(File.dirname(f_path))
       zip_file.extract(f, f_path) unless File.exist?(f_path)
     }
    }
  end

  ## recourse method for creating hierarhy of groups (taxons)
  def add_groups_recourse(current_groups, parent_group, groups_hash)
    current_groups.xpath("Группа").each do |group|
      name = group.xpath("Наименование").text
      id = group.xpath("Ид").text
      groups_hash[id] = []
      unless(parent_group == nil)
	groups_hash[id] = groups_hash[id] + groups_hash[parent_group]
      end
      groups_hash[id] << name
      log("#{id} => #{groups_hash[id]}")
      add_groups_recourse(group.xpath("Группы"), id, groups_hash)
    end
  end



  # create_product_using
  # This method performs the meaty bit of the import - taking the parameters for the
  # product we have gathered, and creating the product and related objects.
  # It also logs throughout the method to try and give some indication of process.
  def create_product_using(params_hash)
####################################################################
####################################################################
####################################################################
     variants_to_update = Variant.where(:sku => params_hash[:sku]).all
     if (variants_to_update.size == 0) 
	begin
	#need create new product
	log("Creating new product...")
	product = Product.new

	#Log which product we're processing
	log(params_hash[:name])

	#The product is inclined to complain if we just dump all params
	# What this does is only assigns values to products if the product accepts that field.
	params_hash.each do |field, value|
		if field != :images && field != :taxonomy
			product.send("#{field}=", value) if product.respond_to?("#{field}=")
		end
	end

	#We can't continue without a valid product here
	unless product.valid?
		log("A product could not be imported - here is the information we have:\n" +
		  "#{pp params_hash}, :error")
		return false
	end
	
	product.save

	#Associate our new product with any taxonomies that we need to worry about
	associate_product_with_taxon(product, IMPORT_PRODUCT_SETTINGS[:taxonomy_name], params_hash[:taxonomy])

	#Finally, attach any images that have been specified
	params_hash[:images].each do |field|
		find_and_attach_image_to(product, field)
	end

	#Log a success message
	log("#{product.name} successfully imported.\n")
     end
     else
	#need update old product
	log("Updating old products...")
	variants_to_update.each { |variant|
		product = Product.where(:id => variant.product_id).first
		#Log which product we're processing
		log(product.name)
		params_hash.each do |field, value|
			if field != :images && field != :taxonomy
				product.send("#{field}=", value) if product.respond_to?("#{field}=")
			end
		end
		product.deleted_at = nil

		#We can't continue without a valid product here
		unless product.valid?
			log("A product could not be updated - here is the information we have:\n" +
			  "#{pp params_hash}, :error")
		end
		
		product.save
		log("Updated")		
	}
     end
####################################################################
####################################################################
####################################################################
    return true
  end

  ### MISC HELPERS ####

  #Log a message to a file - logs in standard Rails format to logfile set up in the import_products initializer
  #and console.
  #Message is string, severity symbol - either :info, :warn or :error

  def log(message, severity = :info)
    @rake_log ||= ActiveSupport::BufferedLogger.new(IMPORT_PRODUCT_SETTINGS[:log_to])
    message = "[#{Time.now.to_s(:db)}] [#{severity.to_s.capitalize}] #{message}\n"
    @rake_log.send severity, message
    puts message
  end


  ### IMAGE HELPERS ###

  # find_and_attach_image_to
  # This method attaches images to products. The images may come
  # from a local source (i.e. on disk), or they may be online (HTTP/HTTPS).
  def find_and_attach_image_to(product_or_variant, filename)
    return if filename.blank?

    #The image can be fetched from an HTTP or local source - either method returns a Tempfile
    file = filename =~ /\Ahttp[s]*:\/\// ? fetch_remote_image(filename) : fetch_local_image(filename)
    #An image has an attachment (the image file) and some object which 'views' it
    product_image = Image.new({:attachment => file,
                              :viewable => product_or_variant,
                              :position => product_or_variant.images.length
                              })

    product_or_variant.images << product_image if product_image.save
  end

  # This method is used when we have a set location on disk for
  # images, and the file is accessible to the script.
  # It is basically just a wrapper around basic File IO methods.
  def fetch_local_image(filename)
    #filename = IMPORT_PRODUCT_SETTINGS[:product_image_path] + filename
    unless File.exists?(filename) && File.readable?(filename)
      log("Image #{filename} was not found on the server, so this image was not imported.", :warn)
      return nil
    else
      return File.open(filename, 'rb')
    end
  end


  #This method can be used when the filename matches the format of a URL.
  # It uses open-uri to fetch the file, returning a Tempfile object if it
  # is successful.
  # If it fails, it in the first instance logs the HTTP error (404, 500 etc)
  # If it fails altogether, it logs it and exits the method.
  def fetch_remote_image(filename)
    begin
      open(filename)
    rescue OpenURI::HTTPError => error
      log("Image #{filename} retrival returned #{error.message}, so this image was not imported")
    rescue
      log("Image #{filename} could not be downloaded, so was not imported.")
    end
  end

  ### TAXON HELPERS ###

  # associate_product_with_taxon
  # This method accepts three formats of taxon hierarchy strings which will
  # associate the given products with taxons:
  # 1. A string on it's own will will just find or create the taxon and
  # add the product to it. e.g. taxonomy = "Category", taxon_hierarchy = "Tools" will
  # add the product to the 'Tools' category.
  # 2. A item > item > item structured string will read this like a tree - allowing
  # a particular taxon to be picked out
  # 3. An item > item & item > item will work as above, but will associate multiple
  # taxons with that product. This form should also work with format 1.
  def associate_product_with_taxon(product, taxonomy, taxon_hierarchy)
    return if product.nil? || taxonomy.nil? || taxon_hierarchy.nil?
    #Using find_or_create_by_name is more elegant, but our magical params code automatically downcases
    # the taxonomy name, so unless we are using MySQL, this isn't going to work.
    taxonomy_name = taxonomy
    taxonomy = Taxonomy.find(:first, :conditions => ["lower(name) = ?", taxonomy])
    taxonomy = Taxonomy.create(:name => taxonomy_name.capitalize) if taxonomy.nil?
    taxon_hierarchy.each do |hierarchy|
      last_taxon = taxonomy.root
      if @groups.has_key?(hierarchy)
        @groups[hierarchy].each do |taxon|
          last_taxon = last_taxon.children.find_or_create_by_name_and_taxonomy_id(taxon, taxonomy.id)
        end
        #Spree only needs to know the most detailed taxonomy item
        product.taxons << last_taxon unless product.taxons.include?(last_taxon)
      end
    end
  end


  def taxonomy_import(groups)
    taxonomy = IMPORT_PRODUCT_SETTINGS[:taxonomy_name]
    taxonomy_name = taxonomy
    taxonomy = Taxonomy.find(:first, :conditions => ["lower(name) = ?", taxonomy])
    taxonomy = Taxonomy.create(:name => taxonomy_name.capitalize) if taxonomy.nil?
    groups.each do |key, hierarchy|
      last_taxon = taxonomy.root
      hierarchy.each do |taxon|
        last_taxon = last_taxon.children.find_or_create_by_name_and_taxonomy_id(taxon, taxonomy.id)
      end
    end
  end

  ### END TAXON HELPERS ###

  # May be implemented via decorator if useful:
  #
  #    ProductImport.class_eval do
  #
  #      private
  #
  #      def after_product_built(product, params_hash)
  #        # so something with the product
  #      end
  #    end
  def after_product_built(product, params_hash)
  end
end

