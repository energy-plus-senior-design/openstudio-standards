class ASHRAE9012013 < ASHRAE901
  # @!group AirLoopHVAC

  # Apply multizone vav outdoor air method and
  # adjust multizone VAV damper positions
  # to achieve a system minimum ventilation effectiveness
  # of 0.6 per PNNL.  Hard-size the resulting min OA
  # into the sizing:system object.
  #
  # return [Bool] returns true if successful, false if not
  # @todo move building-type-specific code to Prototype classes
  def air_loop_hvac_apply_multizone_vav_outdoor_air_sizing(air_loop_hvac)
    # First time adjustment:
    # Only applies to multi-zone vav systems
    # exclusion: for Outpatient: (1) both AHU1 and AHU2 in 'DOE Ref Pre-1980' and 'DOE Ref 1980-2004'
    # (2) AHU1 in 2004-2013
    # TODO refactor: move building-type-specific code to Prototype classes
    if air_loop_hvac_multizone_vav_system?(air_loop_hvac) && !(air_loop_hvac.name.to_s.include? 'Outpatient F1')
      air_loop_hvac_adjust_minimum_vav_damper_positions(air_loop_hvac)
    end

    # Second time adjustment:
    # Only apply to 2010 and 2013 Outpatient (both AHU1 and AHU2)
    # TODO maybe apply to hospital as well?
    # TODO refactor: move building-type-specific code to Prototype classes
    if air_loop_hvac.name.to_s.include? 'Outpatient'
      air_loop_hvac_adjust_minimum_vav_damper_positions_outpatient(air_loop_hvac)
    end

    return true
  end

  # Determine the limits for the type of economizer present
  # on the AirLoopHVAC, if any.
  # @return [Array<Double>] [drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  def air_loop_hvac_economizer_limits(air_loop_hvac, climate_zone)
    drybulb_limit_f = nil
    enthalpy_limit_btu_per_lb = nil
    dewpoint_limit_f = nil

    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    if oa_sys.is_initialized
      oa_sys = oa_sys.get
    else
      return [nil, nil, nil] # No OA system
    end
    oa_control = oa_sys.getControllerOutdoorAir
    economizer_type = oa_control.getEconomizerControlType

    case economizer_type
    when 'NoEconomizer'
      return [nil, nil, nil]
    when 'FixedDryBulb'
      case climate_zone
      when 'ASHRAE 169-2006-1B',
           'ASHRAE 169-2006-2B',
           'ASHRAE 169-2006-3B',
           'ASHRAE 169-2006-3C',
           'ASHRAE 169-2006-4B',
           'ASHRAE 169-2006-4C',
           'ASHRAE 169-2006-5B',
           'ASHRAE 169-2006-5C',
           'ASHRAE 169-2006-6B',
           'ASHRAE 169-2006-7A',
           'ASHRAE 169-2006-7B',
           'ASHRAE 169-2006-8A',
           'ASHRAE 169-2006-8B',
           'ASHRAE 169-2013-1B',
           'ASHRAE 169-2013-2B',
           'ASHRAE 169-2013-3B',
           'ASHRAE 169-2013-3C',
           'ASHRAE 169-2013-4B',
           'ASHRAE 169-2013-4C',
           'ASHRAE 169-2013-5B',
           'ASHRAE 169-2013-5C',
           'ASHRAE 169-2013-6B',
           'ASHRAE 169-2013-7A',
           'ASHRAE 169-2013-7B',
           'ASHRAE 169-2013-8A',
           'ASHRAE 169-2013-8B'
        drybulb_limit_f = 75
      when 'ASHRAE 169-2006-5A',
           'ASHRAE 169-2006-6A',
           'ASHRAE 169-2013-5A',
           'ASHRAE 169-2013-6A'
        drybulb_limit_f = 70
      end
    when 'FixedEnthalpy'
      enthalpy_limit_btu_per_lb = 28
    when 'FixedDewPointAndDryBulb'
      drybulb_limit_f = 75
      dewpoint_limit_f = 55
    end

    return [drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  end

  # Determine if the system economizer must be integrated or not.
  # All economizers must be integrated in 90.1-2013
  def air_loop_hvac_integrated_economizer_required?(air_loop_hvac, climate_zone)
    integrated_economizer_required = true
    return integrated_economizer_required
  end

  # Determine the economizer type and limits for the the PRM
  # Defaults to 90.1-2007 logic.
  # @return [Array<Double>] [economizer_type, drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  def air_loop_hvac_prm_economizer_type_and_limits(air_loop_hvac, climate_zone)
    economizer_type = 'NoEconomizer'
    drybulb_limit_f = nil
    enthalpy_limit_btu_per_lb = nil
    dewpoint_limit_f = nil

    case climate_zone
    when 'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2006-4B',
         'ASHRAE 169-2006-4C',
         'ASHRAE 169-2006-5B',
         'ASHRAE 169-2006-5C',
         'ASHRAE 169-2006-6B',
         'ASHRAE 169-2006-7B',
         'ASHRAE 169-2006-8A',
         'ASHRAE 169-2006-8B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C',
         'ASHRAE 169-2013-4B',
         'ASHRAE 169-2013-4C',
         'ASHRAE 169-2013-5B',
         'ASHRAE 169-2013-5C',
         'ASHRAE 169-2013-6B',
         'ASHRAE 169-2013-7B',
         'ASHRAE 169-2013-8A',
         'ASHRAE 169-2013-8B'
      economizer_type = 'FixedDryBulb'
      drybulb_limit_f = 75
    when 'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2006-4A',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-3A',
         'ASHRAE 169-2013-4A'
      economizer_type = 'FixedEnthalpy'
      enthalpy_limit_btu_per_lb = 28
    when 'ASHRAE 169-2006-5A',
         'ASHRAE 169-2006-6A',
         'ASHRAE 169-2006-7A',
         'ASHRAE 169-2013-5A',
         'ASHRAE 169-2013-6A',
         'ASHRAE 169-2013-7A'
      economizer_type = 'FixedDryBulb'
      drybulb_limit_f = 70
    else
      economizer_type = 'FixedDryBulb'
      drybulb_limit_f = 65
    end

    return [economizer_type, drybulb_limit_f, enthalpy_limit_btu_per_lb, dewpoint_limit_f]
  end

  # Check the economizer type currently specified in the ControllerOutdoorAir object on this air loop
  # is acceptable per the standard.
  #
  # @param (see #economizer_required?)
  # @return [Bool] Returns true if allowable, if the system has no economizer or no OA system.
  # Returns false if the economizer type is not allowable.
  def air_loop_hvac_economizer_type_allowable?(air_loop_hvac, climate_zone)
    # EnergyPlus economizer types
    # 'NoEconomizer'
    # 'FixedDryBulb'
    # 'FixedEnthalpy'
    # 'DifferentialDryBulb'
    # 'DifferentialEnthalpy'
    # 'FixedDewPointAndDryBulb'
    # 'ElectronicEnthalpy'
    # 'DifferentialDryBulbAndEnthalpy'

    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    if oa_sys.is_initialized
      oa_sys = oa_sys.get
    else
      return true # No OA system
    end
    oa_control = oa_sys.getControllerOutdoorAir
    economizer_type = oa_control.getEconomizerControlType

    # Return true if no economizer is present
    if economizer_type == 'NoEconomizer'
      return true
    end

    # Determine the prohibited types
    prohibited_types = []
    case climate_zone
    when 'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2006-4B',
         'ASHRAE 169-2006-4C',
         'ASHRAE 169-2006-5B',
         'ASHRAE 169-2006-6B',
         'ASHRAE 169-2006-7A',
         'ASHRAE 169-2006-7B',
         'ASHRAE 169-2006-8A',
         'ASHRAE 169-2006-8B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C',
         'ASHRAE 169-2013-4B',
         'ASHRAE 169-2013-4C',
         'ASHRAE 169-2013-5B',
         'ASHRAE 169-2013-6B',
         'ASHRAE 169-2013-7A',
         'ASHRAE 169-2013-7B',
         'ASHRAE 169-2013-8A',
         'ASHRAE 169-2013-8B'
      prohibited_types = ['FixedEnthalpy']
    when 'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2006-4A',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-3A',
         'ASHRAE 169-2013-4A'
      prohibited_types = ['FixedDryBulb', 'DifferentialDryBulb']
    when 'ASHRAE 169-2006-5A',
         'ASHRAE 169-2006-6A',
         'ASHRAE 169-2013-5A',
         'ASHRAE 169-2013-6A'
      prohibited_types = []
    end

    # Check if the specified type is allowed
    economizer_type_allowed = true
    if prohibited_types.include?(economizer_type)
      economizer_type_allowed = false
    end

    return economizer_type_allowed
  end

  # Determine if multizone vav optimization is required.
  #
  # @param (see #economizer_required?)
  # @return [Bool] Returns true if required, false if not.
  # @todo Add exception logic for
  #   systems with AIA healthcare ventilation requirements
  #   dual duct systems
  def air_loop_hvac_multizone_vav_optimization_required?(air_loop_hvac, climate_zone)
    multizone_opt_required = false

    # Not required for systems with fan-powered terminals
    num_fan_powered_terminals = 0
    air_loop_hvac.demandComponents.each do |comp|
      if comp.to_AirTerminalSingleDuctParallelPIUReheat.is_initialized || comp.to_AirTerminalSingleDuctSeriesPIUReheat.is_initialized
        num_fan_powered_terminals += 1
      end
    end
    if num_fan_powered_terminals > 0
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, multizone vav optimization is not required because the system has #{num_fan_powered_terminals} fan-powered terminals.")
      return multizone_opt_required
    end

    # Not required for systems that require an ERV
    if air_loop_hvac_energy_recovery?(air_loop_hvac)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: multizone vav optimization is not required because the system has Energy Recovery.")
      return multizone_opt_required
    end

    # Get the OA intake
    controller_oa = nil
    controller_mv = nil
    oa_system = nil
    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      controller_mv = controller_oa.controllerMechanicalVentilation
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, multizone optimization is not applicable because system has no OA intake.")
      return multizone_opt_required
    end

    # Get the AHU design supply air flow rate
    dsn_flow_m3_per_s = nil
    if air_loop_hvac.designSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
    elsif air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} design supply air flow rate is not available, cannot apply efficiency standard.")
      return multizone_opt_required
    end
    dsn_flow_cfm = OpenStudio.convert(dsn_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Get the minimum OA flow rate
    min_oa_flow_m3_per_s = nil
    if controller_oa.minimumOutdoorAirFlowRate.is_initialized
      min_oa_flow_m3_per_s = controller_oa.minimumOutdoorAirFlowRate.get
    elsif controller_oa.autosizedMinimumOutdoorAirFlowRate.is_initialized
      min_oa_flow_m3_per_s = controller_oa.autosizedMinimumOutdoorAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{controller_oa.name}: minimum OA flow rate is not available, cannot apply efficiency standard.")
      return multizone_opt_required
    end
    min_oa_flow_cfm = OpenStudio.convert(min_oa_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Calculate the percent OA at design airflow
    pct_oa = min_oa_flow_m3_per_s / dsn_flow_m3_per_s

    # Not required for systems where
    # exhaust is more than 70% of the total OA intake.
    if pct_oa > 0.7
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{controller_oa.name}: multizone optimization is not applicable because system is more than 70% OA.")
      return multizone_opt_required
    end

    # TODO: Not required for dual-duct systems
    # if self.isDualDuct
    # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.AirLoopHVAC", "For #{controller_oa.name}: multizone optimization is not applicable because it is a dual duct system")
    # return multizone_opt_required
    # end

    # If here, multizone vav optimization is required
    multizone_opt_required = true

    return multizone_opt_required
  end

  # Determines the OA flow rates above which an economizer is required.
  # Two separate rates, one for systems with an economizer and another
  # for systems without.
  # are zero for both types.
  # @return [Array<Double>] [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  def air_loop_hvac_demand_control_ventilation_limits(air_loop_hvac)
    min_oa_without_economizer_cfm = 3000
    min_oa_with_economizer_cfm = 750
    return [min_oa_without_economizer_cfm, min_oa_with_economizer_cfm]
  end

  # Determine the air flow and number of story limits
  # for whether motorized OA damper is required.
  # @return [Array<Double>] [minimum_oa_flow_cfm, maximum_stories]
  def air_loop_hvac_motorized_oa_damper_limits(air_loop_hvac, climate_zone)
    case climate_zone
    when 'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3A',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C'
      minimum_oa_flow_cfm = 0
      maximum_stories = 999 # Any number of stories
    else
      minimum_oa_flow_cfm = 0
      maximum_stories = 0
    end

    return [minimum_oa_flow_cfm, maximum_stories]
  end

  # Determine the number of stages that should be used as controls
  # for single zone DX systems.  90.1-2013 depends on the cooling
  # capacity of the system.
  #
  # @return [Integer] the number of stages: 0, 1, 2
  def air_loop_hvac_single_zone_controls_num_stages(air_loop_hvac, climate_zone)
    min_clg_cap_btu_per_hr = 65_000
    clg_cap_btu_per_hr = OpenStudio.convert(air_loop_hvac_total_cooling_capacity(air_loop_hvac), 'W', 'Btu/hr').get
    if clg_cap_btu_per_hr >= min_clg_cap_btu_per_hr
      num_stages = 2
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: two-stage control is required since cooling capacity of #{clg_cap_btu_per_hr.round} Btu/hr exceeds the minimum of #{min_clg_cap_btu_per_hr.round} Btu/hr .")
    else
      num_stages = 1
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: two-stage control is not required since cooling capacity of #{clg_cap_btu_per_hr.round} Btu/hr is less than the minimum of #{min_clg_cap_btu_per_hr.round} Btu/hr .")
    end

    return num_stages
  end

  # Determine if the system required supply air temperature
  # (SAT) reset. For 90.1-2013, SAT reset requirements are based on climate zone.
  #
  # @param (see #economizer_required?)
  # @return [Bool] Returns true if required, false if not.
  def air_loop_hvac_supply_air_temperature_reset_required?(air_loop_hvac, climate_zone)
    is_sat_reset_required = false

    # Only required for multizone VAV systems
    unless air_loop_hvac_multizone_vav_system?(air_loop_hvac)
      return is_sat_reset_required
    end

    case climate_zone
    when 'ASHRAE 169-2006-1A',
         'ASHRAE 169-2006-2A',
         'ASHRAE 169-2006-3A',
         'ASHRAE 169-2013-1A',
         'ASHRAE 169-2013-2A',
         'ASHRAE 169-2013-3A'
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Supply air temperature reset is not required per 6.5.3.4 Exception 1, the system is located in climate zone #{climate_zone}.")
      return is_sat_reset_required
    when 'ASHRAE 169-2006-1B',
         'ASHRAE 169-2006-2B',
         'ASHRAE 169-2006-3B',
         'ASHRAE 169-2006-3C',
         'ASHRAE 169-2006-4A',
         'ASHRAE 169-2006-4B',
         'ASHRAE 169-2006-4C',
         'ASHRAE 169-2006-5A',
         'ASHRAE 169-2006-5B',
         'ASHRAE 169-2006-5C',
         'ASHRAE 169-2006-6A',
         'ASHRAE 169-2006-6B',
         'ASHRAE 169-2006-7A',
         'ASHRAE 169-2006-7B',
         'ASHRAE 169-2006-8A',
         'ASHRAE 169-2006-8B',
         'ASHRAE 169-2013-1B',
         'ASHRAE 169-2013-2B',
         'ASHRAE 169-2013-3B',
         'ASHRAE 169-2013-3C',
         'ASHRAE 169-2013-4A',
         'ASHRAE 169-2013-4B',
         'ASHRAE 169-2013-4C',
         'ASHRAE 169-2013-5A',
         'ASHRAE 169-2013-5B',
         'ASHRAE 169-2013-5C',
         'ASHRAE 169-2013-6A',
         'ASHRAE 169-2013-6B',
         'ASHRAE 169-2013-7A',
         'ASHRAE 169-2013-7B',
         'ASHRAE 169-2013-8A',
         'ASHRAE 169-2013-8B'
      is_sat_reset_required = true
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: Supply air temperature reset is required.")
      return is_sat_reset_required
    end
  end

  # Determine the airflow limits that govern whether or not
  # an ERV is required.  Based on climate zone and % OA, plus
  # the number of operating hours the system has.
  # @return [Double] the flow rate above which an ERV is required.
  # if nil, ERV is never required.
  def air_loop_hvac_energy_recovery_ventilator_flow_limit(air_loop_hvac, climate_zone, pct_oa)
    # Calculate the number of system operating hours
    # based on the availability schedule.
    ann_op_hrs = 0.0
    avail_sch = air_loop_hvac.availabilitySchedule
    if avail_sch == air_loop_hvac.model.alwaysOnDiscreteSchedule
      ann_op_hrs = 8760.0
    elsif avail_sch.to_ScheduleRuleset.is_initialized
      avail_sch = avail_sch.to_ScheduleRuleset.get
      ann_op_hrs = schedule_ruleset_annual_hours_above_value(avail_sch, 0.0)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: could not determine annual operating hours. Assuming less than 8,000 for ERV determination.")
    end

    if ann_op_hrs < 8000.0
      # Table 6.5.6.1-1, less than 8000 hrs
      case climate_zone
      when 'ASHRAE 169-2006-3B',
           'ASHRAE 169-2006-3C',
           'ASHRAE 169-2006-4B',
           'ASHRAE 169-2006-4C',
           'ASHRAE 169-2006-5B',
           'ASHRAE 169-2013-3B',
           'ASHRAE 169-2013-3C',
           'ASHRAE 169-2013-4B',
           'ASHRAE 169-2013-4C',
           'ASHRAE 169-2013-5B'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1 && pct_oa < 0.2
          erv_cfm = nil
        elsif pct_oa >= 0.2 && pct_oa < 0.3
          erv_cfm = nil
        elsif pct_oa >= 0.3 && pct_oa < 0.4
          erv_cfm = nil
        elsif pct_oa >= 0.4 && pct_oa < 0.5
          erv_cfm = nil
        elsif pct_oa >= 0.5 && pct_oa < 0.6
          erv_cfm = nil
        elsif pct_oa >= 0.6 && pct_oa < 0.7
          erv_cfm = nil
        elsif pct_oa >= 0.7 && pct_oa < 0.8
          erv_cfm = nil
        elsif pct_oa >= 0.8
          erv_cfm = nil
        end
      when 'ASHRAE 169-2006-1B',
           'ASHRAE 169-2006-2B',
           'ASHRAE 169-2006-5C',
           'ASHRAE 169-2013-1B',
           'ASHRAE 169-2013-2B',
           'ASHRAE 169-2013-5C'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1 && pct_oa < 0.2
          erv_cfm = nil
        elsif pct_oa >= 0.2 && pct_oa < 0.3
          erv_cfm = nil
        elsif pct_oa >= 0.3 && pct_oa < 0.4
          erv_cfm = nil
        elsif pct_oa >= 0.4 && pct_oa < 0.5
          erv_cfm = nil
        elsif pct_oa >= 0.5 && pct_oa < 0.6
          erv_cfm = 26_000
        elsif pct_oa >= 0.6 && pct_oa < 0.7
          erv_cfm = 12_000
        elsif pct_oa >= 0.7 && pct_oa < 0.8
          erv_cfm = 5000
        elsif pct_oa >= 0.8
          erv_cfm = 4000
        end
      when 'ASHRAE 169-2006-6B',
           'ASHRAE 169-2013-6B'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1 && pct_oa < 0.2
          erv_cfm = 28_000
        elsif pct_oa >= 0.2 && pct_oa < 0.3
          erv_cfm = 26_500
        elsif pct_oa >= 0.3 && pct_oa < 0.4
          erv_cfm = 11_000
        elsif pct_oa >= 0.4 && pct_oa < 0.5
          erv_cfm = 5500
        elsif pct_oa >= 0.5 && pct_oa < 0.6
          erv_cfm = 4500
        elsif pct_oa >= 0.6 && pct_oa < 0.7
          erv_cfm = 3500
        elsif pct_oa >= 0.7 && pct_oa < 0.8
          erv_cfm = 2500
        elsif pct_oa >= 0.8
          erv_cfm = 1500
        end
      when 'ASHRAE 169-2006-1A',
           'ASHRAE 169-2006-2A',
           'ASHRAE 169-2006-3A',
           'ASHRAE 169-2006-4A',
           'ASHRAE 169-2006-5A',
           'ASHRAE 169-2006-6A',
           'ASHRAE 169-2013-1A',
           'ASHRAE 169-2013-2A',
           'ASHRAE 169-2013-3A',
           'ASHRAE 169-2013-4A',
           'ASHRAE 169-2013-5A',
           'ASHRAE 169-2013-6A'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1 && pct_oa < 0.2
          erv_cfm = 26_000
        elsif pct_oa >= 0.2 && pct_oa < 0.3
          erv_cfm = 16_000
        elsif pct_oa >= 0.3 && pct_oa < 0.4
          erv_cfm = 5500
        elsif pct_oa >= 0.4 && pct_oa < 0.5
          erv_cfm = 4500
        elsif pct_oa >= 0.5 && pct_oa < 0.6
          erv_cfm = 3500
        elsif pct_oa >= 0.6 && pct_oa < 0.7
          erv_cfm = 2000
        elsif pct_oa >= 0.7 && pct_oa < 0.8
          erv_cfm = 1000
        elsif pct_oa >= 0.8
          erv_cfm = 0
        end
      when 'ASHRAE 169-2006-7A',
           'ASHRAE 169-2006-7B',
           'ASHRAE 169-2006-8A',
           'ASHRAE 169-2006-8B',
           'ASHRAE 169-2013-7A',
           'ASHRAE 169-2013-7B',
           'ASHRAE 169-2013-8A',
           'ASHRAE 169-2013-8B'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1 && pct_oa < 0.2
          erv_cfm = 4500
        elsif pct_oa >= 0.2 && pct_oa < 0.3
          erv_cfm = 4000
        elsif pct_oa >= 0.3 && pct_oa < 0.4
          erv_cfm = 2500
        elsif pct_oa >= 0.4 && pct_oa < 0.5
          erv_cfm = 1000
        elsif pct_oa >= 0.5 && pct_oa < 0.6
          erv_cfm = 0
        elsif pct_oa >= 0.6 && pct_oa < 0.7
          erv_cfm = 0
        elsif pct_oa >= 0.7 && pct_oa < 0.8
          erv_cfm = 0
        elsif pct_oa >= 0.8
          erv_cfm = 0
        end
      end
    else
      # Table 6.5.6.1-2, above 8000 hrs
      case climate_zone
      when 'ASHRAE 169-2006-3C',
           'ASHRAE 169-2013-3C'
        erv_cfm = nil
      when 'ASHRAE 169-2006-1B',
           'ASHRAE 169-2006-2B',
           'ASHRAE 169-2006-3B',
           'ASHRAE 169-2006-4C',
           'ASHRAE 169-2006-5C',
           'ASHRAE 169-2013-1B',
           'ASHRAE 169-2013-2B',
           'ASHRAE 169-2013-3B',
           'ASHRAE 169-2013-4C',
           'ASHRAE 169-2013-5C'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1 && pct_oa < 0.2
          erv_cfm = nil
        elsif pct_oa >= 0.2 && pct_oa < 0.3
          erv_cfm = 19_500
        elsif pct_oa >= 0.3 && pct_oa < 0.4
          erv_cfm = 9000
        elsif pct_oa >= 0.4 && pct_oa < 0.5
          erv_cfm = 5000
        elsif pct_oa >= 0.5 && pct_oa < 0.6
          erv_cfm = 4000
        elsif pct_oa >= 0.6 && pct_oa < 0.7
          erv_cfm = 3000
        elsif pct_oa >= 0.7 && pct_oa < 0.8
          erv_cfm = 1500
        elsif pct_oa >= 0.8
          erv_cfm = 0
        end
      when 'ASHRAE 169-2006-1A',
           'ASHRAE 169-2006-2A',
           'ASHRAE 169-2006-3A',
           'ASHRAE 169-2006-4B',
           'ASHRAE 169-2006-5B',
           'ASHRAE 169-2013-1A',
           'ASHRAE 169-2013-2A',
           'ASHRAE 169-2013-3A',
           'ASHRAE 169-2013-4B',
           'ASHRAE 169-2013-5B'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1 && pct_oa < 0.2
          erv_cfm = 2500
        elsif pct_oa >= 0.2 && pct_oa < 0.3
          erv_cfm = 2000
        elsif pct_oa >= 0.3 && pct_oa < 0.4
          erv_cfm = 1000
        elsif pct_oa >= 0.4 && pct_oa < 0.5
          erv_cfm = 500
        elsif pct_oa >= 0.5
          erv_cfm = 0
        end
      when 'ASHRAE 169-2006-4A',
           'ASHRAE 169-2006-5A',
           'ASHRAE 169-2006-6A',
           'ASHRAE 169-2006-6B',
           'ASHRAE 169-2006-7A',
           'ASHRAE 169-2006-7B',
           'ASHRAE 169-2006-8A',
           'ASHRAE 169-2006-8B',
           'ASHRAE 169-2013-4A',
           'ASHRAE 169-2013-5A',
           'ASHRAE 169-2013-6A',
           'ASHRAE 169-2013-6B',
           'ASHRAE 169-2013-7A',
           'ASHRAE 169-2013-7B',
           'ASHRAE 169-2013-8A',
           'ASHRAE 169-2013-8B'
        if pct_oa < 0.1
          erv_cfm = nil
        elsif pct_oa >= 0.1
          erv_cfm = 0
        end
      end
    end

    return erv_cfm
  end
end
