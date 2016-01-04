class Api::UtterancesController < ApplicationController
  before_filter :require_api_token, :except => [:show]
  
  def show
    utterance = Utterance.find_by_global_id(params['id'])
    return unless exists?(utterance)
    return unless allowed?(utterance, 'view')
    render json: JsonApi::Utterance.as_json(utterance, :wrapper => true, :permissions => @api_user).to_json
  end
  
  def create
    utterance = Utterance.process_new(params['utterance'], {:user => @api_user})
    if !utterance || utterance.errored?
      api_error(400, {error: "utterance creation failed", errors: utterance.processing_errors})
    else
      render json: JsonApi::Utterance.as_json(utterance, :wrapper => true, :permissions => @api_user).to_json
    end
  end

  def update
    utterance = Utterance.find_by_global_id(params['id'])
    return unless exists?(utterance)
    return unless allowed?(utterance, 'edit')
    if utterance.process(params['utterance'])
      render json: JsonApi::Utterance.as_json(utterance, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error(400, {error: "utterance update failed", errors: utterance.processing_errors})
    end
  end
end
