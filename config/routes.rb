Rails.application.routes.draw do
    namespace :admin do
      resources :product_imports, :only => [:index, :new, :create]
      match 'product_imports/clear' => "product_imports#clear"
    end
end
