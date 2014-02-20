class TripsController < ApplicationController
  doorkeeper_for :create, :update, :destroy, :by_login, :if => lambda { authenticate_with_oauth? }
  before_filter :authenticate_user!, :except => [:index, :show, :by_login], :unless => lambda { authenticated_with_oauth? }
  before_filter :load_record, :only => [:show, :edit, :update, :destroy]
  before_filter :require_owner, :only => [:edit, :update, :destroy]
  before_filter :load_form_data, :only => [:new, :edit]
  before_filter :set_feature_test, :only => [:index, :show, :edit]
  before_filter :load_user_by_login, :only => [:by_login]

  layout "bootstrap"

  resource_description do
    description <<-EOT
      Trips are, well, trips. You go out to a place for a set period of time,
      you look for some stuff, hopefully you find some stuff, and then you
      write it up. Here, a Trip is a sublcass of Post, b/c these are
      essentially like blog posts with some added fields. Note that PUT, POST,
      and DELETE requests require an authenticated user who has permission to
      perform these actions (usually the user who created the resource).
    EOT
    formats %w(json)
  end
  
  api :GET, '/trips', 'Retrieve recently created trips'
  param :page, :number, :desc => "Page of results"
  param :per_page, PER_PAGES, :desc => "Results per page"
  def index
    per_page = params[:per_page] unless PER_PAGES.include?(params[:per_page].to_i)
    per_page ||= 30
    @trips = Trip.published.page(params[:page]).per_page(per_page).order("posts.id DESC")

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: {:trips => @trips.as_json} }
    end
  end

  api :GET, '/trips/:login', 'Retrieve recently created trips by a particular user'
  param :login, String, :desc => "User login (username)"
  param :page, :number, :desc => "Page of results"
  param :per_page, PER_PAGES, :desc => "Results per page"
  param :published, [true,false,'any'], :desc => "Whether or not to return draft posts.", :default => true
  def by_login
    per_page = params[:per_page] unless PER_PAGES.include?(params[:per_page].to_i)
    per_page ||= 30
    @trips = Trip.where(:user_id => @selected_user).page(params[:page]).per_page(per_page).order("posts.id DESC")
    if current_user == @selected_user && params[:published].noish?
      @trips = @trips.unpublished
    elsif current_user == @selected_user && params[:published] == 'any'
      # return both
    else
      @trips = @trips.published
    end
    respond_to do |format|
      format.json { render json: {:trips => @trips.as_json} }
    end
  end

  api :GET, '/trips/:id', "Get info about an existing trip"
  param :id, :number, :required => true
  def show
    respond_to do |format|
      format.html do
        @next = @trip.parent.journal_posts.published.where("published_at > ?", @trip.published_at || @trip.updated_at).order("published_at ASC").first
        @prev = @trip.parent.journal_posts.published.where("published_at < ?", @trip.published_at || @trip.updated_at).order("published_at DESC").first
      end
      format.json { render json: @trip.as_json(:root => true) }
    end
  end

  def new
    @trip = Trip.new(:user => current_user)
    respond_to do |format|
      format.html
      format.json { render json: @trip.as_json(:root => true) }
    end
  end

  def edit
    @trip_taxa = @trip.trip_taxa
  end

  api :POST, '/trips', "Create a new trip"
  param :trip, Hash, :required => true, :desc => "Trip info" do
    param :title, String, :required => true
    param :body, String, :desc => "Description of the trip."
    param :latitude, :number, :desc => "Latitude of a point approximating the trip location."
    param :longitude, :number, :desc => "Longitude of a point approximating the trip location."
    param :positional_accuracy, :number, :desc => "Precision of a point approximating the trip location."
    param :place_id, :number, :desc => "Site place ID of place where the trip occurred."
    param :trip_taxa_attributes, Hash, :desc => "
      Nested trip taxa, i.e. taxa on the trip's check list. Note that this
      hash should be indexed uniquely for each trip taxon, e.g. <code>trip[trip_taxa_attributes][0][taxon_id]=xxx</code>
    " do
      param :taxon_id, :number, :desc => "Taxon ID"
      param :observed, [true, false], :desc => "Whether or not the taxon was observed"
    end
    param :trip_purposes_attributes, Hash, :desc => "
      Nested trip purposes, i.e. things sought on the trip (at this time only taxa are supported. Note that this
      hash should be indexed uniquely for each trip purpose, e.g. <code>trip[trip_purposes_attributes][0][taxon_id]=xxx</code>
    " do
      param :resource_type, ['Taxon'], :desc => "Purpose type. Only Taxon for now"
      param :resource_id, :number, :desc => "Taxon ID"
      param :complete, [true,false], :desc => "Whether or not this purposes should be considered accomplished, e.g. the user saught Homo sapiens and found one."
    end
  end
  def create
    @trip = Trip.new(params[:trip])
    @trip.user = current_user
    if params[:publish]
      @trip.published_at = Time.now
    elsif params[:unpublish]
      @trip.published_at = nil
    end

    respond_to do |format|
      if @trip.save
        format.html { redirect_to @trip, notice: 'Trip was successfully created.' }
        format.json { render json: @trip.as_json(:root => true), status: :created, location: @trip }
      else
        format.html { render action: "new" }
        format.json { render json: @trip.errors, status: :unprocessable_entity }
      end
    end
  end

  api :PUT, '/trips/:id', "Update an existing trip"
  param :id, :number, :required => true
  param :trip, Hash, :required => true, :desc => "Trip info" do
    param :title, String, :required => true
    param :body, String, :desc => "Description of the trip."
    param :latitude, :number, :desc => "Latitude of a point approximating the trip location."
    param :longitude, :number, :desc => "Longitude of a point approximating the trip location."
    param :positional_accuracy, :number, :desc => "Precision of a point approximating the trip location."
    param :place_id, :number, :desc => "Site place ID of place where the trip occurred."
    param :trip_taxa_attributes, Hash, :desc => "
      Nested trip taxa, i.e. taxa on the trip's check list. Note that this
      hash should be indexed uniquely for each trip taxon, e.g.
      <code>trip[trip_taxa_attributes][0][taxon_id]=xxx</code>. When updating
      existing trip taxa, make sure you include their IDs, e.g.
      <code>trip[trip_taxa_attributes][0][id]=xxx</code>
    " do
      param :id, :number, :desc => "Trip taxon ID, required if you're updating an existing trip taxon"
      param :taxon_id, :number, :desc => "Taxon ID"
      param :observed, [true, false], :desc => "Whether or not the taxon was observed"
    end
    param :trip_purposes_attributes, Hash, :desc => "
      Nested trip purposes, i.e. things sought on the trip (at this time only
      taxa are supported. Note that this hash should be indexed uniquely for
      each trip taxon, e.g.
      <code>trip[trip_purposes_attributes][0][resource_id]=xxx</code>. When updating
      existing trip purposes, make sure you include their IDs, e.g.
      <code>trip[trip_purposes_attributes][0][id]=xxx</code>
    " do
      param :id, :number, :desc => "Trip purpose ID, required if you're updating an existing trip taxon"
      param :resource_type, ['Taxon'], :desc => "Purpose type. Only Taxon for now"
      param :resource_id, :number, :desc => "Taxon ID"
      param :complete, [true,false], :desc => "Whether or not this purposes should be considered accomplished, e.g. the user saught Homo sapiens and found one."
    end
  end
  def update
    if params[:publish]
      @trip.published_at = Time.now
    elsif params[:unpublish]
      @trip.published_at = nil
    end
    respond_to do |format|
      if @trip.update_attributes(params[:trip])
        format.html { redirect_to @trip, notice: 'Trip was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @trip.errors, status: :unprocessable_entity }
      end
    end
  end

  api :DELETE, "/trips/:id", "Delete an existing trip"
  param :id, :number, :required => true
  def destroy
    @trip.destroy

    respond_to do |format|
      format.html { redirect_to trips_url }
      format.json { head :no_content }
    end
  end

  private

  def load_form_data
    selected_names = %w(Aves Amphibia Reptilia Mammalia)
    @target_taxa = Taxon::ICONIC_TAXA.select{|t| selected_names.include?(t.name)}
    extra = Taxon.where("name in (?)", %w(Papilionoidea Hesperiidae Araneae Basidiomycota Magnoliophyta Pteridophyta))
    @target_taxa += extra
    @target_taxa = Taxon.sort_by_ancestry(@target_taxa)
    @target_taxa.each_with_index do |t,i|
      @target_taxa[i].html = render_to_string(:partial => "shared/taxon", :locals => {:taxon => t})
    end
  end

  def set_feature_test
    @feature_test = "trips"
  end
end