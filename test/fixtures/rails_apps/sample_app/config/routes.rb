Rails.application.routes.draw do
  resources :posts
  get "status", to: "health#show"
  get "ghost", to: "ghosts#index"
end
