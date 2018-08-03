class Ability
  include CanCan::Ability

  def initialize(user)
    return unless user&.region_id?

    can :access, :rails_admin
    can :read, :dashboard
    can :history
    can :manage, [Event, Operator, RegionLinkXref, Zone], region_id: user.region_id
    can %i[read], [UserSubmission], region_id: user.region_id
    can %i[update read], [LocationPictureXref], location: { region_id: user.region_id }
    can %i[update read destroy], [MachineCondition, MachineScoreXref], location: { region_id: user.region_id }

    if user.is_super_admin
      can :manage, [Location, User, UserSubmission, SuggestedLocation]
    else
      can :manage, [Location], region_id: user.region_id
      can %i[update read destroy], [SuggestedLocation], region_id: user.region_id
    end

    if user.region.name == 'portland'
      can :manage, [Region, Machine, MachineGroup, BannedIp, LocationType]
    elsif user.is_machine_admin
      can %i[update read], [Region], id: user.region_id
      can :manage, [Machine, MachineGroup]
    else
      can %i[update read], [Region], id: user.region_id
      can %i[read], [Machine]
    end
  end
end
