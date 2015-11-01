class Region < ActiveRecord::Base
  has_many :locations
  has_many :zones
  has_many :users
  has_many :events
  has_many :operators
  has_many :region_link_xrefs
  has_many :user_submissions
  has_many :location_machine_xrefs, through: :locations

  attr_accessible :name, :full_name, :motd, :lat, :lon, :n_search_no, :default_search_type, :should_email_machine_removal

  geocoded_by :lat_and_lon, latitude: :lat, longitude: :lon

  def machines
    machines = {}
    location_machine_xrefs.includes(:machine).each do |lmx|
      machines[lmx.machine.id] = lmx.machine
    end

    machines.values.sort_by(&:name)
  end

  def machine_score_xrefs
    machine_score_xrefs = []

    location_machine_xrefs.includes(:machine_score_xrefs, :location, :machine).each do |lmx|
      machine_score_xrefs += lmx.machine_score_xrefs if lmx.machine_score_xrefs
    end

    machine_score_xrefs
  end

  def n_recent_scores(n)
    scores = machine_score_xrefs.sort_by(&:id)
    scores[0, n]
  end

  def n_high_rollers(n = 10)
    rollers = {}
    @high_rollers = {}

    machine_score_xrefs.each do |msx|
      (rollers[msx.initials] ||= []) << msx
    end

    rollers.sort { |a, b| b[1].size <=> a[1].size }.each do |roller|
      initials = roller[0]
      scores = roller[1]
      scores.sort! { |a, b| b.created_at <=> a.created_at }

      @high_rollers[initials] = scores unless @high_rollers.size == n
    end

    @high_rollers
  end

  def all_admin_email_addresses
    if users.empty?
      ['email_not_found@noemailfound.noemail']
    else
      users.map { |u| u.email }.sort
    end
  end

  def primary_email_contact
    if users.empty?
      'email_not_found@noemailfound.noemail'
    elsif users.any? { |u| u.is_primary_email_contact }
      primary_email_contact = users.find { |u| u.is_primary_email_contact }
      primary_email_contact.email
    else
      users[0].email
    end
  end

  def machineless_locations
    machineless_locations = []

    locations.each { |l| machineless_locations.push(l) unless l.machines.size > 0 }

    machineless_locations
  end

  def locations_count
    Location.count_by_sql "select count(*) from locations where region_id=#{id}"
  end

  def machines_count
    LocationMachineXref.count_by_sql "select count(*) from location_machine_xrefs lmx inner join locations l on (lmx.location_id = l.id) where l.region_id=#{id}"
  end

  def available_search_sections
    sections = %w(city location machine type)

    sections.push('operator') if operators.size > 0

    sections.push('zone') if zones.size > 0

    '[' + sections.map { |s| "'" + s + "'" }.join(', ') + ']'
  end

  def content_for_infowindow
    content = "'<div class=\"infowindow\" id=\"infowindow_#{id}\">"
    content += "<div class=\"gm_region_name\"><a href=\"#{name}\">#{full_name.gsub("'", "\\\\'")}</a></div>"
    content += '<hr />'
    content += "<div class=\"gm_location_count\">#{locations.size} Locations</div>"
    content += "<div class=\"gm_machine_count\">#{location_machine_xrefs.size} Machines</div>"
    content += "</div>'"

    content.html_safe
  end

  def filtered_region_links
    links = {}
    region_link_xrefs.each do |rlx|
      (links[(rlx.category && !rlx.category.blank?) ? rlx.category : 'Links'] ||= []) << rlx
    end

    links
  end

  def lat_and_lon
    [lat, lon].join(', ')
  end

  def generate_weekly_admin_email_body
    start_of_week = (DateTime.now - 1.week).beginning_of_day
    end_of_week = DateTime.now.end_of_day

    <<HERE
Here's an overview of your pinball map region! Thanks for keeping your region updated! Please remove any empty locations and add any submitted ones. Questions/concerns? Contact pinballmap@posteo.org

#{full_name} Weekly Overview

List of Empty Locations:
#{machineless_locations.each.map { |ml| ml.name + " (#{ml.city}, #{ml.state})" }.sort.join("\n")}

#{user_submissions.select { |us| !us.created_at.nil? && us.created_at.between?(start_of_week, end_of_week) && us.submission_type == UserSubmission::SUGGEST_LOCATION_TYPE }.count} Location(s) were submitted to you this week
#{locations.select { |l| !l.created_at.nil? && l.created_at.between?(start_of_week, end_of_week) }.count} Location(s) were added by you this week
#{location_machine_xrefs.select { |lmx| !lmx.created_at.nil? && lmx.created_at.between?(start_of_week, end_of_week) }.count} machines were added by users this week
#{user_submissions.select { |us| !us.created_at.nil? && us.created_at.between?(start_of_week, end_of_week) && us.submission_type == UserSubmission::REMOVE_MACHINE_TYPE }.count} machines were removed by users this week
#{full_name} is listing #{machines_count} machines and #{locations_count} locations
#{events.select {|e| (e.end_date.nil? || e.end_date >= Date.today) }.count } events are listed
#{events.select { |e| !e.created_at.nil? && e.created_at.between?(start_of_week, end_of_week) && (e.end_date.nil? || e.end_date >= Date.today) }.count} events were added this week
#{user_submissions.select { |us| !us.created_at.nil? && us.created_at.between?(start_of_week, end_of_week) && us.submission_type == UserSubmission::CONTACT_US_TYPE }.count} "contact us" messages were sent to you
HERE
  end

  def delete_all_empty_locations
    return unless should_auto_delete_empty_locations

    locations.each do |l|
      l.destroy if (l.location_machine_xrefs.count == 0)
    end
  end
end
