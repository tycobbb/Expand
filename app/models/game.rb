# == Schema Information
#
# Table name: games
#
#  id                  :integer         not null, primary key
#  created_at          :datetime        not null
#  updated_at          :datetime        not null
#  status              :integer
#  board               :string(255)
#  game_description_id :integer
#

class Game < ActiveRecord::Base
  
  before_validation :set_default_status, :on => :create
  after_commit :set_proposing_player, :on => :create
  before_update :start_game_setup
  
  PROPOSED = 0; STARTED = 1; FINISHED = 2
  
  has_many :players, :dependent => :destroy
  has_many :users, :through => :players
  belongs_to :game_description

  attr_accessible :players, :players_attributes, :status, :proposing_player, :game_description
  accepts_nested_attributes_for :players, :allow_destroy => true
  
  validates :status, :numericality => :true, :inclusion => { :in => [ PROPOSED, STARTED, FINISHED ] }
  validate :validate_number_of_players
  
  def validate_number_of_players
    self.errors.add(:base, "Game must have at least 2 players") if self.players.reject(&:marked_for_destruction?).length < 2
  end
     
  def set_default_status
    self.status ||= PROPOSED
  end
  
  def set_proposing_player
    self.players.each do |player|
      if self.proposing_player == player.user_id
        self.proposing_player = player.id
        self.save
        break
      end
    end
  end
  
  def start_game_setup
    if(self.status_was == PROPOSED and self.status == STARTED and !self.game_description_id)
      start
    end
  end
  
  def start
    # Ensure status is indeed started
    self.status ||= STARTED
    # Make sure we have assigned ourselves a game description
    self.game_description_id ||= 1
    # Now load said description by id
    self.game_description = GameDescription.find(game_description_id)
    # Setup the board as all empty
    self.board = "e" * (self.game_description.height * self.game_description.width)
  end

  # queries
  def self.get_proposed_games_for(current_user)
    players_array = Player.includes([:game]).all(:conditions => ['user_id = ? AND games.status = ?', current_user.id, Game::PROPOSED])
    games_string = players_array.inject(' AND (') { |string, player| string += "p.game_id = #{player.game_id} OR " }
    players_array = ActiveRecord::Base.connection.execute(
      'SELECT DISTINCT p.id AS player_id, p.game_id AS game_id, p.accepted AS accepted, u.email AS email 
        FROM users u, players p WHERE u.id = p.user_id' + ((games_string.length > 6) ? (games_string[0..-5]) + ')' : '')
    );

    players_array.size.times do |i|
      players_array[i] = players_array[i].delete_if { |key, value| key.kind_of? Integer } 
    end
    players_array.group_by { |player| player["game_id"] }
  end
  
  def self.get_ready_game_for(current_user)
    game = Game.includes([:players]).first(:conditions =>
      ['game_id = players.game_id AND proposing_player = players.id AND status = ? AND players.user_id = ?', 
        Game::PROPOSED, current_user.id]
    )
    return nil unless game
    players_are_ready = game.players.inject(true) { |is_ready, player| is_ready &&= player.accepted }
    other_player_emails = User.includes([:players]).all(:select => :email, :conditions =>
      ['user_id = players.user_id AND players.game_id = ? AND NOT user_id = ?', game.id, current_user.id]
    ).map(&:email)
    { :game_id => game.id, :other_players => other_player_emails } if players_are_ready
  end

  # this might work
  def find_empty_tile
    find_empty_tile_r(board, 0, rand(self.board.length))
  end
  
  def find_empty_tile(sub_board, start_index, check_index)
    if sub_board[check_index] == 'e'
      return start_index + check_index
    elsif sub_board.length == 1
      return nil
    end
    
    sub_boards = [sub_board[0..check_index-1], sub_board[check_index+1..sub_board.length-1]]
    if rand(2) == 0
      return_index = find_empty_tile(sub_boards[0], start_index, check_index / 2)
      return_index = find_empty_tile(sub_boards[1], start_index + check_index + 1, check_index / 2) unless return_index 
    else
      return_index = find_empty_tile(sub_boards[1], start_index + check_index + 1, check_index / 2) 
      return_index = find_empty_tile(sub_boards[0], start_index, check_index / 2) unless return_index
    end  
    return_index
  end
  
end
