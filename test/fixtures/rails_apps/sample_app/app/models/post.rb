class Post < ApplicationRecord
  belongs_to :user

  # TODO: extract publishing behavior once the API stabilizes.
  def publish!
    if title && user
      update!(published_at: Time.now)
    end
  end
end
