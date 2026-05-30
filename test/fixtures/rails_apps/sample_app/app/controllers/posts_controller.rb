class PostsController < ApplicationController
  def index
    @posts = Post.all
  end

  def show
  end

  def archive
    head :ok
  end
end
