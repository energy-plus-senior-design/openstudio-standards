class NECB2011
  def model_add_hvac(model:)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started Adding HVAC')
    system_fuel_defaults = self.get_canadian_system_defaults_by_weatherfile_name(model)
    necb_autozone_and_autosystem(model: model, runner: nil, use_ideal_air_loads: false, system_fuel_defaults: system_fuel_defaults)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding HVAC')
    return true
  end



  # NECB does not change damper positions
  #
  # return [Bool] returns true if successful, false if not
  def air_loop_hvac_apply_multizone_vav_outdoor_air_sizing(air_loop_hvac)
    # Do not change anything.
    return true
  end

  # Determine whether or not this system
  # is required to have an economizer.
  #
  # @return [Bool] returns true if an economizer is required, false if not
  def air_loop_hvac_economizer_required?(air_loop_hvac)
    economizer_required = false

    # need a better way to determine if an economizer is needed.
    return economizer_required if air_loop_hvac.name.to_s.include? 'Outpatient F1'

    # A big number of btu per hr as the minimum requirement
    infinity_btu_per_hr = 999_999_999_999
    minimum_capacity_btu_per_hr = infinity_btu_per_hr

    # Determine if the airloop serves any computer rooms
    # / data centers, which changes the economizer.
    is_dc = false
    if air_loop_hvac_data_center_area_served(air_loop_hvac) > 0
      is_dc = true
    end

    # Determine the minimum capacity that requires an economizer
    minimum_capacity_btu_per_hr = 68_243 # NECB requires economizer for cooling cap > 20 kW

    # puts air_loop_hvac.name.to_s
    # Design Supply Air Flow Rate: This method below reads the value from the sql file.
    dsafr_m3_per_s = air_loop_hvac.model.getAutosizedValue(air_loop_hvac, 'Design Supply Air Flow Rate', 'm3/s')
    min_dsafr_l_per_s = 1500
    unless dsafr_m3_per_s.empty?
      dsafr_l_per_s = dsafr_m3_per_s.get() * 1000
      if dsafr_l_per_s > min_dsafr_l_per_s
        economizer_required = true
        puts "economizer_required = true for #{air_loop_hvac.name} because dsafr_l_per_s(#{dsafr_l_per_s}) > 1500"
        if is_dc
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the 'Design Supply Air Flow Rate' of #{dsafr_l_per_s} L/s exceeds the minimum air flow rate of #{min_dsafr_l_per_s} L/s for data centers.")
        else
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the 'Design Supply Air Flow Rate' of #{dsafr_l_per_s} L/s exceeds the minimum air flow rate of #{min_dsafr_l_per_s} L/s.")
        end
      end
    end
    # Check whether the system requires an economizer by comparing
    # the system capacity to the minimum capacity.
    total_cooling_capacity_w = air_loop_hvac_total_cooling_capacity(air_loop_hvac)
    total_cooling_capacity_btu_per_hr = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    if total_cooling_capacity_btu_per_hr >= minimum_capacity_btu_per_hr
      if is_dc
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr for data centers.")
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} requires an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr.")
      end
      puts "economizer_required = true for #{air_loop_hvac.name} because total_cooling_capacity_btu_per_hr(#{total_cooling_capacity_btu_per_hr}) >= #{minimum_capacity_btu_per_hr}"
      economizer_required = true
    else
      if is_dc
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} does not require an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr is less than the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr for data centers.")
      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "#{air_loop_hvac.name} does not require an economizer because the total cooling capacity of #{total_cooling_capacity_btu_per_hr.round} Btu/hr is less than the minimum capacity of #{minimum_capacity_btu_per_hr.round} Btu/hr.")
      end
    end

    return economizer_required
  end

  # NECB always requires an integrated economizer
  # (NoLockout); as per 5.2.2.8(3)
  # this means that compressor allowed to turn on when economizer is open
  #
  # @note this method assumes you previously checked that an economizer is required at all
  #   via #economizer_required?
  # @param (see #economizer_required?)
  # @return [Bool] returns true if successful, false if not
  def air_loop_hvac_apply_economizer_integration(air_loop_hvac, climate_zone)
    # Get the OA system and OA controller
    oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
    if oa_sys.is_initialized
      oa_sys = oa_sys.get
    else
      return false # No OA system
    end
    oa_control = oa_sys.getControllerOutdoorAir

    # Apply integrated economizer
    oa_control.setLockoutType('NoLockout')

    return true
  end

  # Check if ERV is required on this airloop.
  #
  # @param (see #economizer_required?)
  # @return [Bool] Returns true if required, false if not.
  # @todo Add exception logic for systems serving parking garage, warehouse, or multifamily
  def air_loop_hvac_energy_recovery_ventilator_required?(air_loop_hvac, climate_zone)
    # ERV Not Applicable for AHUs that serve
    # parking garage, warehouse, or multifamily
    # if space_types_served_names.include?('PNNL_Asset_Rating_Apartment_Space_Type') ||
    # space_types_served_names.include?('PNNL_Asset_Rating_LowRiseApartment_Space_Type') ||
    # space_types_served_names.include?('PNNL_Asset_Rating_ParkingGarage_Space_Type') ||
    # space_types_served_names.include?('PNNL_Asset_Rating_Warehouse_Space_Type')
    # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.AirLoopHVAC", "For #{self.name}, ERV not applicable because it because it serves parking garage, warehouse, or multifamily.")
    # return false
    # end

    erv_required = nil
    # ERV not applicable for medical AHUs (AHU1 in Outpatient), per AIA 2001 - 7.31.D2.
    if air_loop_hvac.name.to_s.include? 'Outpatient F1'
      erv_required = false
      return erv_required
    end

    # ERV not applicable for medical AHUs, per AIA 2001 - 7.31.D2.
    if air_loop_hvac.name.to_s.include? 'VAV_ER'
      erv_required = false
      return erv_required
    elsif air_loop_hvac.name.to_s.include? 'VAV_OR'
      erv_required = false
      return erv_required
    end

    # ERV Not Applicable for AHUs that have DCV
    # or that have no OA intake.
    controller_oa = nil
    controller_mv = nil
    oa_system = nil
    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      controller_mv = controller_oa.controllerMechanicalVentilation
      if controller_mv.demandControlledVentilation == true
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not applicable because DCV enabled.")
        return false
      end
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not applicable because it has no OA intake.")
      return false
    end

    # Get the AHU design supply air flow rate
    dsn_flow_m3_per_s = nil
    if air_loop_hvac.designSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.designSupplyAirFlowRate.get
    elsif air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
      dsn_flow_m3_per_s = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name} design supply air flow rate is not available, cannot apply efficiency standard.")
      return false
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
      return false
    end
    min_oa_flow_cfm = OpenStudio.convert(min_oa_flow_m3_per_s, 'm^3/s', 'cfm').get

    # Calculate the percent OA at design airflow
    pct_oa = min_oa_flow_m3_per_s / dsn_flow_m3_per_s

    # The NECB2011 requirement is that systems with an exhaust heat content > 150 kW require an HRV
    # The calculation for this is done below, to modify erv_required
    # erv_cfm set to nil here as placeholder, will lead to erv_required = false
    erv_cfm = nil

    # Determine if an ERV is required
    # erv_required = nil
    if erv_cfm.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not required based on #{(pct_oa * 100).round}% OA flow, design supply air flow of #{dsn_flow_cfm.round}cfm, and climate zone #{climate_zone}.")
      erv_required = false
    elsif dsn_flow_cfm < erv_cfm
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not required based on #{(pct_oa * 100).round}% OA flow, design supply air flow of #{dsn_flow_cfm.round}cfm, and climate zone #{climate_zone}. Does not exceed minimum flow requirement of #{erv_cfm}cfm.")
      erv_required = false
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV required based on #{(pct_oa * 100).round}% OA flow, design supply air flow of #{dsn_flow_cfm.round}cfm, and climate zone #{climate_zone}. Exceeds minimum flow requirement of #{erv_cfm}cfm.")
      erv_required = true
    end

    # This code modifies erv_required for NECB2011
    # Calculation of exhaust heat content and check whether it is > 150 kW

    # get all zones in the model
    zones = air_loop_hvac.thermalZones

    # initialize counters
    sum_zone_oa = 0.0
    sum_zone_oa_times_heat_design_t = 0.0

    # zone loop
    zones.each do |zone|
      # get design heat temperature for each zone; this is equivalent to design exhaust temperature
      heat_design_t = 21.0
      zone_thermostat = zone.thermostat.get
      if zone_thermostat.to_ThermostatSetpointDualSetpoint.is_initialized
        dual_thermostat = zone_thermostat.to_ThermostatSetpointDualSetpoint.get
        htg_temp_sch = dual_thermostat.heatingSetpointTemperatureSchedule.get
        htg_temp_sch_ruleset = htg_temp_sch.to_ScheduleRuleset.get
        winter_dd_sch = htg_temp_sch_ruleset.winterDesignDaySchedule
        heat_design_t = winter_dd_sch.values.max
      end

      # initialize counter
      zone_oa = 0.0
      # outdoor defined at space level; get OA flow for all spaces within zone
      spaces = zone.spaces

      # space loop
      spaces.each do |space|
        unless space.designSpecificationOutdoorAir.empty? # if empty, don't do anything
          outdoor_air = space.designSpecificationOutdoorAir.get
          # in bTAP, outdoor air specified as outdoor air per
          oa_flow_per_floor_area = outdoor_air.outdoorAirFlowperFloorArea
          oa_flow = oa_flow_per_floor_area * space.floorArea * zone.multiplier # oa flow for the space
          zone_oa += oa_flow # add up oa flow for all spaces to get zone air flow
        end
      end # space loop
      sum_zone_oa += zone_oa # sum of all zone oa flows to get system oa flow
      sum_zone_oa_times_heat_design_t += (zone_oa * heat_design_t) # calculated to get oa flow weighted average of design exhaust temperature
    end # zone loop

    # Calculate average exhaust temperature (oa flow weighted average)
    avg_exhaust_temp = sum_zone_oa_times_heat_design_t / sum_zone_oa

    # for debugging/testing
    #      puts "average exhaust temp = #{avg_exhaust_temp}"
    #      puts "sum_zone_oa = #{sum_zone_oa}"

    # Get January winter design temperature
    # get model weather file name
    weather_file = BTAP::Environment::WeatherFile.new(air_loop_hvac.model.weatherFile.get.path.get)

    # get winter(heating) design temp stored in array
    # Note that the NECB2011 specifies using the 2.5% january design temperature
    # The outdoor temperature used here is the 0.4% heating design temperature of the coldest month, available in stat file
    outdoor_temp = weather_file.heating_design_info[1]

    #      for debugging/testing
    #      puts "outdoor design temp = #{outdoor_temp}"

    # Calculate exhaust heat content
    exhaust_heat_content = 0.00123 * sum_zone_oa * 1000.0 * (avg_exhaust_temp - outdoor_temp)

    # for debugging/testing
    #      puts "exhaust heat content = #{exhaust_heat_content}"

    # Modify erv_required based on exhaust heat content
    if exhaust_heat_content > 150.0
      erv_required = true
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV required based on exhaust heat content.")
    else
      erv_required = false
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV not required based on exhaust heat content.")
    end

    return erv_required
  end

  # Add an ERV to this airloop.
  # Will be a rotary-type HX
  #
  # @param (see #economizer_required?)
  # @return [Bool] Returns true if required, false if not.
  # @todo Add exception logic for systems serving parking garage, warehouse, or multifamily
  def air_loop_hvac_apply_energy_recovery_ventilator(air_loop_hvac)
    # Get the oa system
    oa_system = nil
    if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV cannot be added because the system has no OA intake.")
      return false
    end

    # Create an ERV
    erv = OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(air_loop_hvac.model)
    erv.setName("#{air_loop_hvac.name} ERV")
    erv.setSensibleEffectivenessat100HeatingAirFlow(0.5)
    erv.setLatentEffectivenessat100HeatingAirFlow(0.5)
    erv.setSensibleEffectivenessat75HeatingAirFlow(0.5)
    erv.setLatentEffectivenessat75HeatingAirFlow(0.5)
    erv.setSensibleEffectivenessat100CoolingAirFlow(0.5)
    erv.setLatentEffectivenessat100CoolingAirFlow(0.5)
    erv.setSensibleEffectivenessat75CoolingAirFlow(0.5)
    erv.setLatentEffectivenessat75CoolingAirFlow(0.5)
    erv.setSupplyAirOutletTemperatureControl(true)
    erv.setHeatExchangerType('Rotary')
    erv.setFrostControlType('ExhaustOnly')
    erv.setEconomizerLockout(true)
    erv.setThresholdTemperature(-23.3) # -10F
    erv.setInitialDefrostTimeFraction(0.167)
    erv.setRateofDefrostTimeFractionIncrease(1.44)

    # Add the ERV to the OA system
    erv.addToNode(oa_system.outboardOANode.get)

    # Add a setpoint manager OA pretreat
    # to control the ERV
    spm_oa_pretreat = OpenStudio::Model::SetpointManagerOutdoorAirPretreat.new(air_loop_hvac.model)
    spm_oa_pretreat.setMinimumSetpointTemperature(-99.0)
    spm_oa_pretreat.setMaximumSetpointTemperature(99.0)
    spm_oa_pretreat.setMinimumSetpointHumidityRatio(0.00001)
    spm_oa_pretreat.setMaximumSetpointHumidityRatio(1.0)
    # Reference setpoint node and
    # Mixed air stream node are outlet
    # node of the OA system
    mixed_air_node = oa_system.mixedAirModelObject.get.to_Node.get
    spm_oa_pretreat.setReferenceSetpointNode(mixed_air_node)
    spm_oa_pretreat.setMixedAirStreamNode(mixed_air_node)
    # Outdoor air node is
    # the outboard OA node of teh OA system
    spm_oa_pretreat.setOutdoorAirStreamNode(oa_system.outboardOANode.get)
    # Return air node is the inlet
    # node of the OA system
    return_air_node = oa_system.returnAirModelObject.get.to_Node.get
    spm_oa_pretreat.setReturnAirStreamNode(return_air_node)
    # Attach to the outlet of the ERV
    erv_outlet = erv.primaryAirOutletModelObject.get.to_Node.get
    spm_oa_pretreat.addToNode(erv_outlet)

    # Apply the prototype Heat Exchanger power assumptions.
    heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_nominal_electric_power(erv)

    # Determine if the system is a DOAS based on
    # whether there is 100% OA in heating and cooling sizing.
    is_doas = false
    sizing_system = air_loop_hvac.sizingSystem
    if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating
      is_doas = true
    end

    # Set the bypass control type
    # If DOAS system, BypassWhenWithinEconomizerLimits
    # to disable ERV during economizing.
    # Otherwise, BypassWhenOAFlowGreaterThanMinimum
    # to disable ERV during economizing and when OA
    # is also greater than minimum.
    bypass_ctrl_type = if is_doas
                         'BypassWhenWithinEconomizerLimits'
                       else
                         'BypassWhenOAFlowGreaterThanMinimum'
                       end
    oa_system.getControllerOutdoorAir.setHeatRecoveryBypassControlType(bypass_ctrl_type)

    return true
  end

  # Determine if demand control ventilation (DCV) is
  # required for this air loop.
  #
  # @param (see #economizer_required?)
  # @return [Bool] Returns true if required, false if not.
  # @todo Add exception logic for
  #   systems that serve multifamily, parking garage, warehouse
  def air_loop_hvac_demand_control_ventilation_required?(air_loop_hvac, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{template} #{climate_zone}:  #{air_loop_hvac.name}: DCV is not required for any system.")
    dcv_required = false
    return dcv_required
  end

  # Set the VAV damper control to single maximum or
  # dual maximum control depending on the standard.
  #
  # @return [Bool] Returns true if successful, false if not
  # @todo see if this impacts the sizing run.
  def air_loop_hvac_apply_vav_damper_action(air_loop_hvac)
    damper_action = 'Single Maximum'

    # Interpret this as an EnergyPlus input
    damper_action_eplus = nil
    if damper_action == 'Single Maximum'
      damper_action_eplus = 'Normal'
    elsif damper_action == 'Dual Maximum'
      # EnergyPlus 8.7 changed the meaning of 'Reverse'.
      # For versions of OpenStudio using E+ 8.6 or lower
      damper_action_eplus = if air_loop_hvac.model.version < OpenStudio::VersionString.new('2.0.5')
                              'Reverse'
                              # For versions of OpenStudio using E+ 8.7 or higher
                            else
                              'ReverseWithLimits'
                            end
    end

    # Set the control for any VAV reheat terminals
    # on this airloop.
    control_type_set = false
    air_loop_hvac.demandComponents.each do |equip|
      if equip.to_AirTerminalSingleDuctVAVReheat.is_initialized
        term = equip.to_AirTerminalSingleDuctVAVReheat.get
        # Dual maximum only applies to terminals with HW reheat coils
        if damper_action == 'Dual Maximum'
          if term.reheatCoil.to_CoilHeatingWater.is_initialized
            term.setDamperHeatingAction(damper_action_eplus)
            control_type_set = true
          end
        else
          term.setDamperHeatingAction(damper_action_eplus)
          control_type_set = true
          term.setMaximumFlowFractionDuringReheat(0.5)
        end
      end
    end

    if control_type_set
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: VAV damper action was set to #{damper_action} control.")
    end

    return true
  end

  # NECB has no single zone air loop control requirements
  #
  # @return [Bool] returns true if successful, false if not
  def air_loop_hvac_apply_single_zone_controls(air_loop_hvac, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}: No special economizer controls were modeled.")
    return true
  end

  # NECB doesn't require static pressure reset.
  #
  # return [Bool] returns true if static pressure reset is required, false if not
  def air_loop_hvac_static_pressure_reset_required?(air_loop_hvac, has_ddc)
    # static pressure reset not required
    sp_reset_required = false
    return sp_reset_required
  end

  # Determine the air flow and number of story limits
  # for whether motorized OA damper is required.
  # @return [Array<Double>] [minimum_oa_flow_cfm, maximum_stories].
  # If both nil, never required
  def air_loop_hvac_motorized_oa_damper_limits(air_loop_hvac, climate_zone)
    minimum_oa_flow_cfm = 0
    maximum_stories = 0
    return [minimum_oa_flow_cfm, maximum_stories]
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param boiler_hot_water [OpenStudio::Model::BoilerHotWater] the object to modify
  # @return [Bool] true if successful, false if not
  def boiler_hot_water_apply_efficiency_and_curves(boiler_hot_water)
    successfully_set_all_properties = false

    # Define the criteria to find the boiler properties
    # in the hvac standards data set.
    search_criteria = boiler_hot_water_find_search_criteria(boiler_hot_water)
    fuel_type = search_criteria['fuel_type']
    fluid_type = search_criteria['fluid_type']

    # Get the capacity
    capacity_w = boiler_hot_water_find_capacity(boiler_hot_water)

    # Check if secondary and/or modulating boiler required
    if capacity_w / 1000.0 >= 352.0
      if boiler_hot_water.name.to_s.include?('Primary Boiler')
        boiler_capacity = capacity_w
        boiler_hot_water.setBoilerFlowMode('LeavingSetpointModulated')
        boiler_hot_water.setMinimumPartLoadRatio(0.25)
      elsif boiler_hot_water.name.to_s.include?('Secondary Boiler')
        boiler_capacity = 0.001
      end
    elsif ((capacity_w / 1000.0) >= 176.0) && ((capacity_w / 1000.0) < 352.0)
      boiler_capacity = capacity_w / 2
    elsif (capacity_w / 1000.0) <= 176.0
      if boiler_hot_water.name.to_s.include?('Primary Boiler')
        boiler_capacity = capacity_w
      elsif boiler_hot_water.name.to_s.include?('Secondary Boiler')
        boiler_capacity = 0.001
      end
    end
    boiler_hot_water.setNominalCapacity(boiler_capacity)

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(boiler_capacity, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(boiler_capacity, 'W', 'kBtu/hr').get

    # Get the boiler properties
    boiler_table = @standards_data['boilers']
    blr_props = model_find_object(boiler_table, search_criteria, capacity_btu_per_hr)
    unless blr_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.BoilerHotWater', "For #{boiler_hot_water.name}, cannot find boiler properties, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the EFFFPLR curve
    eff_fplr = model_add_curve(boiler_hot_water.model, blr_props['efffplr'])
    if eff_fplr
      boiler_hot_water.setNormalizedBoilerEfficiencyCurve(eff_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.BoilerHotWater', "For #{boiler_hot_water.name}, cannot find eff_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Get the minimum efficiency standards
    thermal_eff = nil

    # If specified as AFUE
    unless blr_props['minimum_annual_fuel_utilization_efficiency'].nil?
      min_afue = blr_props['minimum_annual_fuel_utilization_efficiency']
      thermal_eff = afue_to_thermal_eff(min_afue)
      new_comp_name = "#{boiler_hot_water.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_afue} AFUE"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.BoilerHotWater', "For #{template}: #{boiler_hot_water.name}: #{fuel_type} #{fluid_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; AFUE = #{min_afue}")
    end

    # If specified as thermal efficiency
    unless blr_props['minimum_thermal_efficiency'].nil?
      thermal_eff = blr_props['minimum_thermal_efficiency']
      new_comp_name = "#{boiler_hot_water.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{thermal_eff} Thermal Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.BoilerHotWater', "For #{template}: #{boiler_hot_water.name}: #{fuel_type} #{fluid_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Thermal Efficiency = #{thermal_eff}")
    end

    # If specified as combustion efficiency
    unless blr_props['minimum_combustion_efficiency'].nil?
      min_comb_eff = blr_props['minimum_combustion_efficiency']
      thermal_eff = combustion_eff_to_thermal_eff(min_comb_eff)
      new_comp_name = "#{boiler_hot_water.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_comb_eff} Combustion Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.BoilerHotWater', "For #{template}: #{boiler_hot_water.name}: #{fuel_type} #{fluid_type} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Combustion Efficiency = #{min_comb_eff}")
    end

    # Set the name
    boiler_hot_water.setName(new_comp_name)

    # Set the efficiency values
    unless thermal_eff.nil?
      boiler_hot_water.setNominalThermalEfficiency(thermal_eff)
    end

    return successfully_set_all_properties
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Bool] true if successful, false if not
  def chiller_electric_eir_apply_efficiency_and_curves(chiller_electric_eir, clg_tower_objs)
    chillers = standards_data['chillers']

    # Define the criteria to find the chiller properties
    # in the hvac standards data set.
    search_criteria = chiller_electric_eir_find_search_criteria(chiller_electric_eir)
    cooling_type = search_criteria['cooling_type']
    condenser_type = search_criteria['condenser_type']
    compressor_type = search_criteria['compressor_type']

    # Get the chiller capacity
    capacity_w = chiller_electric_eir_find_capacity(chiller_electric_eir)

    # All chillers must be modulating down to 25% of their capacity
    chiller_electric_eir.setChillerFlowMode('LeavingSetpointModulated')
    chiller_electric_eir.setMinimumPartLoadRatio(0.25)
    chiller_electric_eir.setMinimumUnloadingRatio(0.25)
    if (capacity_w / 1000.0) < 2100.0
      if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
        chiller_capacity = capacity_w
      elsif chiller_electric_eir.name.to_s.include? 'Secondary Chiller'
        chiller_capacity = 0.001
      end
    else
      chiller_capacity = capacity_w / 2.0
    end
    chiller_electric_eir.setReferenceCapacity(chiller_capacity)

    # Convert capacity to tons
    capacity_tons = OpenStudio.convert(chiller_capacity, 'W', 'ton').get

    # Get the chiller properties
    chlr_table = @standards_data['chillers']
    chlr_props = model_find_object(chlr_table, search_criteria, capacity_tons, Date.today)
    unless chlr_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find chiller properties, cannot apply standard efficiencies or curves.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the CAPFT curve
    cool_cap_ft = model_add_curve(chiller_electric_eir.model, chlr_props['capft'])
    if cool_cap_ft
      chiller_electric_eir.setCoolingCapacityFunctionOfTemperature(cool_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFT curve
    cool_eir_ft = model_add_curve(chiller_electric_eir.model, chlr_props['eirft'])
    if cool_eir_ft
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfTemperature(cool_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the EIRFPLR curve
    # which may be either a CurveBicubic or a CurveQuadratic based on chiller type
    cool_plf_fplr = model_add_curve(chiller_electric_eir.model, chlr_props['eirfplr'])
    if cool_plf_fplr
      chiller_electric_eir.setElectricInputToCoolingOutputRatioFunctionOfPLR(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Set the efficiency value
    kw_per_ton = nil
    cop = nil
    if chlr_props['minimum_full_load_efficiency']
      kw_per_ton = chlr_props['minimum_full_load_efficiency']
      cop = kw_per_ton_to_cop(kw_per_ton)
      chiller_electric_eir.setReferenceCOP(cop)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.ChillerElectricEIR', "For #{chiller_electric_eir.name}, cannot find minimum full load efficiency, will not be set.")
      successfully_set_all_properties = false
    end

    # Set cooling tower properties now that the new COP of the chiller is set
    if chiller_electric_eir.name.to_s.include? 'Primary Chiller'
      # Single speed tower model assumes 25% extra for compressor power
      tower_cap = capacity_w * (1.0 + 1.0 / chiller_electric_eir.referenceCOP)
      if (tower_cap / 1000.0) < 1750
        clg_tower_objs[0].setNumberofCells(1)
      else
        clg_tower_objs[0].setNumberofCells((tower_cap / (1000 * 1750) + 0.5).round)
      end
      clg_tower_objs[0].setFanPoweratDesignAirFlowRate(0.015 * tower_cap)
    end

    # Append the name with size and kw/ton
    chiller_electric_eir.setName("#{chiller_electric_eir.name} #{capacity_tons.round}tons #{kw_per_ton.round(1)}kW/ton")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.ChillerElectricEIR', "For #{template}: #{chiller_electric_eir.name}: #{cooling_type} #{condenser_type} #{compressor_type} Capacity = #{capacity_tons.round}tons; COP = #{cop.round(1)} (#{kw_per_ton.round(1)}kW/ton)")

    return successfully_set_all_properties
  end

  # find search criteria
  #
  # @return [Hash] used for standards_lookup_table(model)
  def coil_heating_gas_find_search_criteria
    # Define the criteria to find the furnace properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template
    search_criteria['fluid_type'] = 'Air'
    search_criteria['fuel_type'] = 'Gas'

    return search_criteria
  end

  # find furnace capacity
  #
  # @return [Hash] used for standards_lookup_table(model)
  def coil_heating_gas_find_capacity(coil_heating_gas)
    # Get the coil capacity
    capacity_w = nil
    if coil_heating_gas.nominalCapacity.is_initialized
      capacity_w = coil_heating_gas.nominalCapacity.get
    elsif coil_heating_gas.autosizedNominalCapacity.is_initialized
      capacity_w = coil_heating_gas.autosizedNominalCapacity.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name} capacity is not available, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    return capacity_w
  end

  # Finds lookup object in standards and return minimum thermal efficiency
  #
  # @return [Double] minimum thermal efficiency
  def coil_heating_gas_standard_minimum_thermal_efficiency(coil_heating_gas, rename = false)

    # Get the coil properties
    search_criteria = coil_heating_gas_find_search_criteria
    capacity_w = coil_heating_gas_find_capacity(coil_heating_gas)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Get the minimum efficiency standards
    thermal_eff = nil

    # Get the coil properties
    coil_table = @standards_data['furnaces']
    coil_props = model_find_object(coil_table, search_criteria, [capacity_btu_per_hr, 0.001].max)

    unless coil_props
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name}, cannot find coil props, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # New name initial value
    new_comp_name = coil_heating_gas.name

    # If specified as AFUE
    unless coil_props['minimum_annual_fuel_utilization_efficiency'].nil?
      min_afue = coil_props['minimum_annual_fuel_utilization_efficiency']
      thermal_eff = afue_to_thermal_eff(min_afue)
      new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_afue} AFUE"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; AFUE = #{min_afue}")
    end

    # If specified as thermal efficiency
    unless coil_props['minimum_thermal_efficiency'].nil?
      thermal_eff = coil_props['minimum_thermal_efficiency']
      new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{thermal_eff} Thermal Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Thermal Efficiency = #{thermal_eff}")
    end

    # If specified as combustion efficiency
    unless coil_props['minimum_combustion_efficiency'].nil?
      min_comb_eff = coil_props['minimum_combustion_efficiency']
      thermal_eff = combustion_eff_to_thermal_eff(min_comb_eff)
      new_comp_name = "#{coil_heating_gas.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_comb_eff} Combustion Eff"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilHeatingGas', "For #{template}: #{coil_heating_gas.name}: Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; Combustion Efficiency = #{min_comb_eff}")
    end

    unless thermal_eff
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{CoilHeatingGas.name}, cannot find coil efficiency, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Rename
    if rename
      coil_heating_gas.setName(new_comp_name)
    end

    return thermal_eff
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Bool] true if successful, false if not
  def coil_heating_gas_apply_efficiency_and_curves(coil_heating_gas)
    successfully_set_all_properties = true

    # Define the search criteria
    search_criteria = coil_heating_gas_find_search_criteria

    # Get the coil capacity
    capacity_w = coil_heating_gas_find_capacity(coil_heating_gas)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get

    # lookup properties
    coil_table = @standards_data['furnaces']
    coil_props = model_find_object(coil_table, search_criteria, [capacity_btu_per_hr, 0.001].max, Date.today)

    # Check to make sure properties were found
    if coil_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name}, cannot find efficiency info using #{search_criteria}, cannot apply efficiency standard.")
      successfully_set_all_properties = false
    end


    # Make the plf vs plr curve
    plffplr_curve = model_add_curve(coil_heating_gas.model, coil_props['efffplr'])
    if plffplr_curve
      coil_heating_gas.setPartLoadFractionCorrelationCurve(plffplr_curve)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGas', "For #{coil_heating_gas.name}, cannot find plffplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Thermal efficiency
    thermal_eff = coil_heating_gas_standard_minimum_thermal_efficiency(coil_heating_gas)

    # Set the efficiency values
    coil_heating_gas.setGasBurnerEfficiency(thermal_eff.to_f)

    return successfully_set_all_properties

  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Bool] true if successful, false if not
  def coil_cooling_dx_multi_speed_apply_efficiency_and_curves(coil_cooling_dx_multi_speed, sql_db_vars_map)
    successfully_set_all_properties = true

    # Define the criteria to find the chiller properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = template
    cooling_type = coil_cooling_dx_multi_speed.condenserType
    search_criteria['cooling_type'] = cooling_type

    # TODO: Standards - add split system vs single package to model
    # For now, assume single package as default
    sub_category = 'Single Package'

    # Determine the heating type if unitary or zone hvac
    heat_pump = false
    heating_type = nil
    containing_comp = nil
    if coil_cooling_dx_multi_speed.airLoopHVAC.empty?
      if coil_cooling_dx_multi_speed.containingHVACComponent.is_initialized
        containing_comp = coil_cooling_dx_multi_speed.containingHVACComponent.get
        if containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.is_initialized
          htg_coil = containing_comp.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get.heatingCoil
          if htg_coil.to_CoilHeatingDXMultiSpeed.is_initialized
            heat_pump = true
            heating_type = 'Electric Resistance or None'
          elsif htg_coil.to_CoilHeatingGasMultiStage.is_initialized
            heating_type = 'All Other'
          end
        end # TODO: Add other unitary systems
      elsif coil_cooling_dx_multi_speed.containingZoneHVACComponent.is_initialized
        containing_comp = coil_cooling_dx_multi_speed.containingZoneHVACComponent.get
        if containing_comp.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          sub_category = 'PTAC'
          htg_coil = containing_comp.to_ZoneHVACPackagedTerminalAirConditioner.get.heatingCoil
          if htg_coil.to_CoilHeatingElectric.is_initialized
            heating_type = 'Electric Resistance or None'
          elsif htg_coil.to_CoilHeatingWater.is_initialized || htg_coil.to_CoilHeatingGas.is_initialized || htg_col.to_CoilHeatingGasMultiStage
            heating_type = 'All Other'
          end
        end # TODO: Add other zone hvac systems
      end
    end

    # Add the heating type to the search criteria
    unless heating_type.nil?
      search_criteria['heating_type'] = heating_type
    end

    search_criteria['subcategory'] = sub_category

    # Get the coil capacity
    capacity_w = nil
    clg_stages = stages
    if clg_stages.last.grossRatedTotalCoolingCapacity.is_initialized
      capacity_w = clg_stages.last.grossRatedTotalCoolingCapacity.get
    elsif coil_cooling_dx_multi_speed.autosizedSpeed4GrossRatedTotalCoolingCapacity.is_initialized
      capacity_w = coil_cooling_dx_multi_speed.autosizedSpeed4GrossRatedTotalCoolingCapacity.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name} capacity is not available, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Volume flow rate
    flow_rate4 = nil
    if clg_stages.last.ratedAirFlowRate.is_initialized
      flow_rate4 = clg_stages.last.ratedAirFlowRate.get
    elsif coil_cooling_dx_multi_speed.autosizedSpeed4RatedAirFlowRate.is_initialized
      flow_rate4 = coil_cooling_dx_multi_speed.autosizedSpeed4RatedAirFlowRate.get
    end

    # Set number of stages
    stage_cap = []
    num_stages = (capacity_w / (66.0 * 1000.0) + 0.5).round
    num_stages = [num_stages, 4].min
    if num_stages == 1
      stage_cap[0] = capacity_w / 2.0
      stage_cap[1] = 2.0 * stage_cap[0]
      stage_cap[2] = stage_cap[1] + 0.1
      stage_cap[3] = stage_cap[2] + 0.1
    else
      stage_cap[0] = 66.0 * 1000.0
      stage_cap[1] = 2.0 * stage_cap[0]
      if num_stages == 2
        stage_cap[2] = stage_cap[1] + 0.1
        stage_cap[3] = stage_cap[2] + 0.1
      elsif num_stages == 3
        stage_cap[2] = 3.0 * stage_cap[0]
        stage_cap[3] = stage_cap[2] + 0.1
      elsif num_stages == 4
        stage_cap[2] = 3.0 * stage_cap[0]
        stage_cap[3] = 4.0 * stage_cap[0]
      end
    end
    # set capacities, flow rates, and sensible heat ratio for stages
    (0..3).each do |istage|
      clg_stages[istage].setGrossRatedTotalCoolingCapacity(stage_cap[istage])
      clg_stages[istage].setRatedAirFlowRate(flow_rate4 * stage_cap[istage] / capacity_w)
    end

    # Convert capacity to Btu/hr
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Lookup efficiencies depending on whether it is a unitary AC or a heat pump
    ac_props = nil
    heat_pump_table = @standards_data['heat_pumps']
    unitary_acs_table = @standards_data['unitary_acs']
    ac_props = if heat_pump == true
                 model_find_object(heat_pump_table, search_criteria, capacity_btu_per_hr, Date.today)
               else
                 model_find_object(unitary_acs_table, search_criteria, capacity_btu_per_hr, Date.today)
               end

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find efficiency info, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Make the COOL-CAP-FT curve
    cool_cap_ft = model_add_curve(model, ac_props['cool_cap_ft'], standards)
    if cool_cap_ft
      clg_stages.each do |stage|
        stage.setTotalCoolingCapacityFunctionofTemperatureCurve(cool_cap_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_cap_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-CAP-FFLOW curve
    cool_cap_fflow = model_add_curve(model, ac_props['cool_cap_fflow'], standards)
    if cool_cap_fflow
      clg_stages.each do |stage|
        stage.setTotalCoolingCapacityFunctionofFlowFractionCurve(cool_cap_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_cap_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FT curve
    cool_eir_ft = model_add_curve(model, ac_props['cool_eir_ft'], standards)
    if cool_eir_ft
      clg_stages.each do |stage|
        stage.setEnergyInputRatioFunctionofTemperatureCurve(cool_eir_ft)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_eir_ft curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-EIR-FFLOW curve
    cool_eir_fflow = model_add_curve(model, ac_props['cool_eir_fflow'], standards)
    if cool_eir_fflow
      clg_stages.each do |stage|
        stage.setEnergyInputRatioFunctionofFlowFractionCurve(cool_eir_fflow)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_eir_fflow curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = model_add_curve(model, ac_props['cool_plf_fplr'], standards)
    if cool_plf_fplr
      clg_stages.each do |stage|
        stage.setPartLoadFractionCorrelationCurve(cool_plf_fplr)
      end
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_cooling_dx_multi_speed.name}, cannot find cool_plf_fplr curve, will not be set.")
      successfully_set_all_properties = false
    end

    # Get the minimum efficiency standards
    cop = nil

    if coil_dx_subcategory(coil_cooling_dx_multi_speed) == 'PTAC'
      ptac_eer_coeff_1 = ac_props['ptac_eer_coefficient_1']
      ptac_eer_coeff_2 = ac_props['ptac_eer_coefficient_2']
      capacity_btu_per_hr = 7000 if capacity_btu_per_hr < 7000
      capacity_btu_per_hr = 15_000 if capacity_btu_per_hr > 15_000
      ptac_eer = ptac_eer_coeff_1 + (ptac_eer_coeff_2 * capacity_btu_per_hr)
      cop = eer_to_cop(ptac_eer)
      # self.setName("#{self.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{ptac_eer}EER")
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{ptac_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{ptac_eer}")
    end

    # If specified as SEER
    unless ac_props['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio']
      cop = seer_to_cop(min_seer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      #      self.setName("#{self.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless ac_props['minimum_energy_efficiency_ratio'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio']
      cop = eer_to_cop(min_eer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # if specified as SEER (heat pump)
    unless ac_props['minimum_seasonal_efficiency'].nil?
      min_seer = ac_props['minimum_seasonal_efficiency']
      cop = seer_to_cop(min_seer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      #      self.setName("#{self.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless ac_props['minimum_full_load_efficiency'].nil?
      min_eer = ac_props['minimum_full_load_efficiency']
      cop = eer_to_cop(min_eer)
      new_comp_name = "#{coil_cooling_dx_multi_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{template}: #{coil_cooling_dx_multi_speed.name}: #{cooling_type} #{heating_type} #{subcategory} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    sql_db_vars_map[new_comp_name] = name.to_s
    coil_cooling_dx_multi_speed.setName(new_comp_name)

    # Set the efficiency values

    unless cop.nil?
      clg_stages.each do |istage|
        istage.setGrossRatedCoolingCOP(cop)
      end
    end

    return sql_db_vars_map
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @return [Bool] true if successful, false if not
  def coil_heating_gas_multi_stage_apply_efficiency_and_curves(coil_heating_gas_multi_stage, standards)
    successfully_set_all_properties = true

    # Get the coil capacity
    capacity_w = nil
    htg_stages = stages
    if htg_stages.last.nominalCapacity.is_initialized
      capacity_w = htg_stages.last.nominalCapacity.get
    elsif coil_heating_gas_multi_stage.autosizedStage4NominalCapacity.is_initialized
      capacity_w = coil_heating_gas_multi_stage.autosizedStage4NominalCapacity.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXMultiSpeed', "For #{coil_heating_gas_multi_stage.name} capacity is not available, cannot apply efficiency standard.")
      successfully_set_all_properties = false
      return successfully_set_all_properties
    end

    # Set number of stages
    num_stages = (capacity_w / (66.0 * 1000.0) + 0.5).round
    num_stages = [num_stages, 4].min
    stage_cap = []
    if num_stages == 1
      stage_cap[0] = capacity_w / 2.0
      stage_cap[1] = 2.0 * stage_cap[0]
      stage_cap[2] = stage_cap[1] + 0.1
      stage_cap[3] = stage_cap[2] + 0.1
    else
      stage_cap[0] = 66.0 * 1000.0
      stage_cap[1] = 2.0 * stage_cap[0]
      if num_stages == 2
        stage_cap[2] = stage_cap[1] + 0.1
        stage_cap[3] = stage_cap[2] + 0.1
      elsif num_stages == 3
        stage_cap[2] = 3.0 * stage_cap[0]
        stage_cap[3] = stage_cap[2] + 0.1
      elsif num_stages == 4
        stage_cap[2] = 3.0 * stage_cap[0]
        stage_cap[3] = 4.0 * stage_cap[0]
      end
    end
    # set capacities, flow rates, and sensible heat ratio for stages
    (0..3).each do |istage|
      htg_stages[istage].setNominalCapacity(stage_cap[istage])
    end
    # PLF vs PLR curve
    furnace_plffplr_curve_name = 'FURNACE-EFFPLR-NECB2011'

    # plf vs plr curve for furnace
    furnace_plffplr_curve = model_add_curve(coil_heating_gas_multi_stage.model, furnace_plffplr_curve_name, standards)
    if furnace_plffplr_curve
      coil_heating_gas_multi_stage.setPartLoadFractionCorrelationCurve(furnace_plffplr_curve)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilHeatingGasMultiStage', "For #{coil_heating_gas_multi_stage.name}, cannot find plffplr curve, will not be set.")
      successfully_set_all_properties = false
    end
  end

  # Determines the baseline fan impeller efficiency
  # based on the specified fan type.
  #
  # @return [Double] impeller efficiency (0.0 to 1.0)
  # @todo Add fan type to data model and modify this method
  def fan_baseline_impeller_efficiency(fan)
    # Assume that the fan efficiency is 65% for normal fans
    # TODO add fan type to fan data model
    # and infer impeller efficiency from that?
    # or do we always assume a certain type of
    # fan impeller for the baseline system?
    # TODO check COMNET and T24 ACM and PNNL 90.1 doc
    fan_impeller_eff = 0.65

    return fan_impeller_eff
  end

  # Determines the minimum fan motor efficiency and nominal size
  # for a given motor bhp.  This should be the total brake horsepower with
  # any desired safety factor already included.  This method picks
  # the next nominal motor catgory larger than the required brake
  # horsepower, and the efficiency is based on that size.  For example,
  # if the bhp = 6.3, the nominal size will be 7.5HP and the efficiency
  # for 90.1-2010 will be 91.7% from Table 10.8B.  This method assumes
  # 4-pole, 1800rpm totally-enclosed fan-cooled motors.
  #
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Array<Double>] minimum motor efficiency (0.0 to 1.0), nominal horsepower
  def fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)
    fan_motor_eff = 0.85
    nominal_hp = motor_bhp

    # Don't attempt to look up motor efficiency
    # for zero-hp fans, which may occur when there is no
    # airflow required for a particular system, typically
    # heated-only spaces with high internal gains
    # and no OA requirements such as elevator shafts.
    return [fan_motor_eff, 0] if motor_bhp == 0.0

    # Lookup the minimum motor efficiency
    motors_table = @standards_data['motors']

    # Assuming all fan motors are 4-pole ODP
    template_mod = @template
    if fan.class.name == 'OpenStudio::Model::FanConstantVolume'
      template_mod += '-CONSTANT'
    elsif fan.class.name == 'OpenStudio::Model::FanVariableVolume'
      # Is this a return or supply fan
      if fan.name.to_s.include?('Supply')
        template_mod += '-VARIABLE-SUPPLY'
      elsif fan.name.to_s.include?('Return')
        template_mod += '-VARIABLE-RETURN'
      end
      # 0.909 corrects for 10% over sizing implemented upstream
      # 0.7457 is to convert from bhp to kW
      fan_power_kw = 0.909 * 0.7457 * motor_bhp
      power_vs_flow_curve_name = if fan_power_kw >= 25.0
                                   'VarVolFan-FCInletVanes-NECB2011-FPLR'
                                 elsif fan_power_kw >= 7.5 && fan_power_kw < 25
                                   'VarVolFan-AFBIInletVanes-NECB2011-FPLR'
                                 else
                                   'VarVolFan-AFBIFanCurve-NECB2011-FPLR'
                                 end
      power_vs_flow_curve = model_add_curve(fan.model, power_vs_flow_curve_name)
      fan.setFanPowerMinimumFlowRateInputMethod('Fraction')
      fan.setFanPowerCoefficient5(0.0)
      fan.setFanPowerMinimumFlowFraction(power_vs_flow_curve.minimumValueofx)
      fan.setFanPowerCoefficient1(power_vs_flow_curve.coefficient1Constant)
      fan.setFanPowerCoefficient2(power_vs_flow_curve.coefficient2x)
      fan.setFanPowerCoefficient3(power_vs_flow_curve.coefficient3xPOW2)
      fan.setFanPowerCoefficient4(power_vs_flow_curve.coefficient4xPOW3)
    else
      raise('')
    end

    search_criteria = {
        'template' => template_mod,
        'number_of_poles' => 4.0,
        'type' => 'Enclosed'
    }

    # Exception for small fans, including
    # zone exhaust, fan coil, and fan powered terminals.
    # In this case, use the 0.5 HP for the lookup.
    if fan_small_fan?(fan)
      nominal_hp = 0.5
    else
      motor_properties = model_find_object(motors_table, search_criteria, motor_bhp)
      if motor_properties.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
        return [fan_motor_eff, nominal_hp]
      end

      nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
      # If the biggest fan motor size is hit, use the highest category efficiency
      if nominal_hp == 9999.0
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Fan', "For #{fan.name}, there is no greater nominal HP.  Use the efficiency of the largest motor category.")
        nominal_hp = motor_bhp
      end

      # Round to nearest whole HP for niceness
      if nominal_hp >= 2
        nominal_hp = nominal_hp.round
      end
    end

    # Get the efficiency based on the nominal horsepower
    # Add 0.01 hp to avoid search errors.
    motor_properties = model_find_object(motors_table, search_criteria, nominal_hp + 0.01)

    if motor_properties.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find nominal motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp.")
      return [fan_motor_eff, nominal_hp]
    end
    fan_motor_eff = motor_properties['nominal_full_load_efficiency']

    return [fan_motor_eff, nominal_hp]
  end

  # Determines whether there is a requirement to have a
  # VSD or some other method to reduce fan power
  # at low part load ratios.
  def fan_variable_volume_part_load_fan_power_limitation?(fan_variable_volume)
    part_load_control_required = false

    return part_load_control_required
  end

  # Determine if demand control ventilation (DCV) is
  # required for this zone based on area and occupant density.
  # Does not account for System requirements like ERV, economizer, etc.
  # Those are accounted for in the AirLoopHVAC method of the same name.
  #
  # @return [Bool] Returns true if required, false if not.
  # @todo Add exception logic for 90.1-2013
  #   for cells, sickrooms, labs, barbers, salons, and bowling alleys
  def thermal_zone_demand_control_ventilation_required?(thermal_zone, climate_zone)
    return false
  end

  def model_apply_sizing_parameters(model)
    model.getSizingParameters.setHeatingSizingFactor(self.get_standards_constant('sizing_factor_max_heating'))
    model.getSizingParameters.setCoolingSizingFactor(self.get_standards_constant('sizing_factor_max_cooling'))
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Set sizing factors to #{self.get_standards_constant('sizing_factor_max_heating')} for heating and #{self.get_standards_constant('sizing_factor_max_heating')} for cooling.")
  end

  def fan_constant_volume_apply_prototype_fan_pressure_rise(fan_constant_volume)
    fan_constant_volume.setPressureRise(self.get_standards_constant('fan_constant_volume_pressure_rise_value'))
    return true
  end

  # Sets the fan pressure rise based on the Prototype buildings inputs
  # which are governed by the flow rate coming through the fan
  # and whether the fan lives inside a unit heater, PTAC, etc.
  def fan_variable_volume_apply_prototype_fan_pressure_rise(fan_variable_volume)
    # 1000 Pa for supply fan and 458.33 Pa for return fan (accounts for efficiency differences between two fans)
    if (fan_variable_volume.name.to_s.include?('Supply'))
      sfan_deltaP = self.get_standards_constant('supply_fan_variable_volume_pressure_rise_value')
      fan_variable_volume.setPressureRise(sfan_deltaP)
    elsif (fan_variable_volume.name.to_s.include?('Return'))
      rfan_deltaP = self.get_standards_constant('return_fan_variable_volume_pressure_rise_value')
      fan_variable_volume.setPressureRise(rfan_deltaP)
    end
    return true
  end

  def apply_economizers(climate_zone, model)
    # NECB2011 prescribes ability to provide 100% OA (5.2.2.7-5.2.2.9)
    econ_max_100_pct_oa_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    econ_max_100_pct_oa_sch.setName('Economizer Max OA Fraction 100 pct')
    econ_max_100_pct_oa_sch.defaultDaySchedule.setName('Economizer Max OA Fraction 100 pct Default')
    econ_max_100_pct_oa_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)

    # Check each airloop
    model.getAirLoopHVACs.sort.each do |air_loop|
      if air_loop_hvac_economizer_required?(air_loop) == true
        # If an economizer is required, determine the economizer type
        # in the prototype buildings, which depends on climate zone.
        economizer_type = nil

        # NECB 5.2.2.8 states that economizer can be controlled based on difference betweeen
        # return air temperature and outside air temperature OR return air enthalpy
        # and outside air enthalphy; latter chosen to be consistent with MNECB and CAN-QUEST implementation
        economizer_type = 'DifferentialEnthalpy'
        # Set the economizer type
        # Get the OA system and OA controller
        oa_sys = air_loop.airLoopHVACOutdoorAirSystem
        if oa_sys.is_initialized
          oa_sys = oa_sys.get
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but it has no OA system.")
          next
        end
        oa_control = oa_sys.getControllerOutdoorAir
        oa_control.setEconomizerControlType(economizer_type)
      end
    end
  end

  def set_zones_thermostat_schedule_based_on_space_type_schedules(model, runner = nil)
    puts 'in set_zones_thermostat_schedule_based_on_space_type_schedules'
    BTAP.runner_register('DEBUG', 'Start-set_zones_thermostat_schedule_based_on_space_type_schedules', runner)
    model.getThermalZones.sort.each do |zone|
      BTAP.runner_register('DEBUG', "Zone = #{zone.name} Spaces =#{zone.spaces.size} ", runner)
      array = []

      zone.spaces.sort.each do |space|
        schedule_type = determine_necb_schedule_type(space).to_s
        BTAP.runner_register('DEBUG', "space name/type:#{space.name}/#{schedule_type}", runner)

        # if wildcard space type, need to get dominant schedule type
        if '*'.to_s == schedule_type
          dominant_sched_type = determine_dominant_necb_schedule_type(model)
          schedule_type = dominant_sched_type
        end

        array << schedule_type
      end
      array.uniq!
      if array.size > 1
        BTAP.runner_register('Error', "#{zone.name} has spaces with different schedule types. Please ensure that all the spaces are of the same schedule type A to I.", runner)
        return false
      end

      htg_search_string = "NECB-#{array[0]}-Thermostat Setpoint-Heating"
      clg_search_string = "NECB-#{array[0]}-Thermostat Setpoint-Cooling"

      if model.getScheduleRulesetByName(htg_search_string).empty? == false
        htg_sched = model.getScheduleRulesetByName(htg_search_string).get
      else
        BTAP.runner_register('ERROR', "heating_thermostat_setpoint_schedule NECB-#{array[0]} does not exist", runner)
        return false
      end

      if model.getScheduleRulesetByName(clg_search_string).empty? == false
        clg_sched = model.getScheduleRulesetByName(clg_search_string).get
      else
        BTAP.runner_register('ERROR', "cooling_thermostat_setpoint_schedule NECB-#{array[0]} does not exist", runner)
        return false
      end

      name = "NECB-#{array[0]}-Thermostat Dual Setpoint Schedule"

      # If dual setpoint already exists, use that one, else create one
      ds = if model.getThermostatSetpointDualSetpointByName(name).empty? == false
             model.getThermostatSetpointDualSetpointByName(name).get
           else
             BTAP::Resources::Schedules.create_annual_thermostat_setpoint_dual_setpoint(model, name, htg_sched, clg_sched)
           end

      thermostat_clone = ds.clone.to_ThermostatSetpointDualSetpoint.get
      zone.setThermostatSetpointDualSetpoint(thermostat_clone)
      BTAP.runner_register('Info', "ThermalZone #{zone.name} set to DualSetpoint Schedule NECB-#{array[0]}", runner)
    end

    BTAP.runner_register('DEBUG', 'END-set_zones_thermostat_schedule_based_on_space_type_schedules', runner)
    return true
  end

  # Helper method to find out which climate zone set contains a specific climate zone.
  # Returns climate zone set name as String if success, nil if not found.
  def model_find_climate_zone_set(model, clim)
    return "NECB-CNEB ClimatZone 4-8"
  end

  def setup_hw_loop_with_components(model,
                                    hw_loop,
                                    boiler_fueltype,
                                    pump_flow_sch)
    hw_loop.setName('Hot Water Loop')
    sizing_plant = hw_loop.sizingPlant
    sizing_plant.setLoopType('Heating')
    sizing_plant.setDesignLoopExitTemperature(82.0) # TODO: units
    sizing_plant.setLoopDesignTemperatureDifference(16.0)

    # pump (set to variable speed for now till fix to run away plant temperature is found)
    # pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump = OpenStudio::Model::PumpVariableSpeed.new(model)
    # TODO: the keyword "setPumpFlowRateSchedule" does not seem to work. A message
    # was sent to NREL to let them know about this. Once there is a fix for this,
    # use the proper pump schedule depending on whether we have two-pipe or four-pipe
    # fan coils.
    #            pump.resetPumpFlowRateSchedule()
    #            pump.setPumpFlowRateSchedule(pump_flow_sch)

    # boiler
    boiler1 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler2 = OpenStudio::Model::BoilerHotWater.new(model)
    boiler1.setFuelType(boiler_fueltype)
    boiler2.setFuelType(boiler_fueltype)
    boiler1.setName('Primary Boiler')
    boiler2.setName('Secondary Boiler')

    # boiler_bypass_pipe
    boiler_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # supply_outlet_pipe
    supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # Add the components to the hot water loop
    hw_supply_inlet_node = hw_loop.supplyInletNode
    hw_supply_outlet_node = hw_loop.supplyOutletNode
    pump.addToNode(hw_supply_inlet_node)

    hw_loop.addSupplyBranchForComponent(boiler1)
    hw_loop.addSupplyBranchForComponent(boiler2)
    hw_loop.addSupplyBranchForComponent(boiler_bypass_pipe)
    supply_outlet_pipe.addToNode(hw_supply_outlet_node)

    # Add a setpoint manager to control the
    # hot water based on outdoor temperature
    hw_oareset_stpt_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
    hw_oareset_stpt_manager.setControlVariable('Temperature')
    hw_oareset_stpt_manager.setSetpointatOutdoorLowTemperature(82.0)
    hw_oareset_stpt_manager.setOutdoorLowTemperature(-16.0)
    hw_oareset_stpt_manager.setSetpointatOutdoorHighTemperature(60.0)
    hw_oareset_stpt_manager.setOutdoorHighTemperature(0.0)
    hw_oareset_stpt_manager.addToNode(hw_supply_outlet_node)
  end

  # of setup_hw_loop_with_components

  def setup_chw_loop_with_components(model, chw_loop, chiller_type)
    chw_loop.setName('Chilled Water Loop')
    sizing_plant = chw_loop.sizingPlant
    sizing_plant.setLoopType('Cooling')
    sizing_plant.setDesignLoopExitTemperature(7.0)
    sizing_plant.setLoopDesignTemperatureDifference(6.0)

    # pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    chw_pump = OpenStudio::Model::PumpConstantSpeed.new(model)

    chiller1 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller2 = OpenStudio::Model::ChillerElectricEIR.new(model)
    chiller1.setCondenserType('WaterCooled')
    chiller2.setCondenserType('WaterCooled')
    chiller1_name = "Primary Chiller WaterCooled #{chiller_type}"
    chiller1.setName(chiller1_name)
    chiller2_name = "Secondary Chiller WaterCooled #{chiller_type}"
    chiller2.setName(chiller2_name)

    chiller_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    chw_supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # Add the components to the chilled water loop
    chw_supply_inlet_node = chw_loop.supplyInletNode
    chw_supply_outlet_node = chw_loop.supplyOutletNode
    chw_pump.addToNode(chw_supply_inlet_node)
    chw_loop.addSupplyBranchForComponent(chiller1)
    chw_loop.addSupplyBranchForComponent(chiller2)
    chw_loop.addSupplyBranchForComponent(chiller_bypass_pipe)
    chw_supply_outlet_pipe.addToNode(chw_supply_outlet_node)

    # Add a setpoint manager to control the
    # chilled water to a constant temperature
    chw_t_c = 7.0
    chw_t_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(model, 'CHW Temp', 'Temperature', chw_t_c)
    chw_t_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, chw_t_sch)
    chw_t_stpt_manager.addToNode(chw_supply_outlet_node)

    return chiller1, chiller2
  end

  # of setup_chw_loop_with_components

  def setup_cw_loop_with_components(model, cw_loop, chiller1, chiller2)
    cw_loop.setName('Condenser Water Loop')
    cw_sizing_plant = cw_loop.sizingPlant
    cw_sizing_plant.setLoopType('Condenser')
    cw_sizing_plant.setDesignLoopExitTemperature(29.0)
    cw_sizing_plant.setLoopDesignTemperatureDifference(6.0)

    cw_pump = OpenStudio::Model::PumpConstantSpeed.new(model)

    clg_tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(model)

    # TO DO: Need to define and set cooling tower curves

    clg_tower_bypass_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    cw_supply_outlet_pipe = OpenStudio::Model::PipeAdiabatic.new(model)

    # Add the components to the condenser water loop
    cw_supply_inlet_node = cw_loop.supplyInletNode
    cw_supply_outlet_node = cw_loop.supplyOutletNode
    cw_pump.addToNode(cw_supply_inlet_node)
    clg_tower.setDesignInletAirWetBulbTemperature(24.0)
    clg_tower.setDesignInletAirDryBulbTemperature(35.0)
    clg_tower.setDesignApproachTemperature(5.0)
    clg_tower.setDesignRangeTemperature(6.0)
    cw_loop.addSupplyBranchForComponent(clg_tower)
    cw_loop.addSupplyBranchForComponent(clg_tower_bypass_pipe)
    cw_supply_outlet_pipe.addToNode(cw_supply_outlet_node)
    cw_loop.addDemandBranchForComponent(chiller1)
    cw_loop.addDemandBranchForComponent(chiller2)

    # Add a setpoint manager to control the
    # condenser water to constant temperature
    cw_t_c = 29.0
    cw_t_sch = BTAP::Resources::Schedules.create_annual_constant_ruleset_schedule(model, 'CW Temp', 'Temperature', cw_t_c)
    cw_t_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, cw_t_sch)
    cw_t_stpt_manager.addToNode(cw_supply_outlet_node)

    return clg_tower
  end


  # Creates thermal zones to contain each space, as defined for each building in the
  # system_to_space_map inside the Prototype.building_name
  # e.g. (Prototype.secondary_school.rb) file.
  #
  # @param (see #add_constructions)
  # @return [Bool] returns true if successful, false if not
  def model_create_thermal_zones(model,
                                 space_multiplier_map = nil)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started creating thermal zones')
    space_multiplier_map = {} if space_multiplier_map.nil?

    # Remove any Thermal zones assigned
    model.getThermalZones.each(&:remove)

    # Create a thermal zone for each space in the self
    model.getSpaces.sort.each do |space|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("#{space.name} ZN")
      unless space_multiplier_map[space.name.to_s].nil? || (space_multiplier_map[space.name.to_s] == 1)
        zone.setMultiplier(space_multiplier_map[space.name.to_s])
      end
      space.setThermalZone(zone)

      # Skip thermostat for spaces with no space type
      next if space.spaceType.empty?

      # Add a thermostat
      space_type_name = space.spaceType.get.name.get
      thermostat_name = space_type_name + ' Thermostat'
      thermostat = model.getThermostatSetpointDualSetpointByName(thermostat_name)
      if thermostat.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Thermostat #{thermostat_name} not found for space name: #{space.name}")
      else
        thermostat_clone = thermostat.get.clone(model).to_ThermostatSetpointDualSetpoint.get
        zone.setThermostatSetpointDualSetpoint(thermostat_clone)
        # Set Ideal loads to thermal zone for sizing for NECB needs. We need this for sizing.
        ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
        ideal_loads.addToThermalZone(zone)
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished creating thermal zones')
  end

  # This method cycles through the spaces in a thermal zone and then sorts them by story.  The method then cycles
  # through the spaces on a story and then calculates the centroid of the spaces in the thermal zone on that floor.  The
  # method returns an array of hashes, one for each story.  Each hash has the following structure:
  #           {
  #               story_name: Name of a given story.
  #               spaces: Array containing all of the spaces in the thermal zone on the story in story_name.
  #               centroid: Array containing the x, y, and z coordinates of the centroid of the ceilings of the spaces
  #                         listed in 'spaces:' above.
  #               ceiling_area: Total area of the ceilings of the spaces in 'spaces:' above.
  #           }
  # Only spaces which are conditioned (heated or cooled) and are not plenums are included.
  def thermal_zone_get_centroid_per_floor(thermal_zone)
    stories = []
    thermal_zone.spaces.sort.each do |space|
      spaceType_name = space.spaceType.get.nameString
      sp_type = spaceType_name[15..-1]
      # Including regular expressions in the following match for cases where extra characters, which do not belong, are
      # added to either the space type in the model or the space type reference file.
      sp_type_info = @standards_data['space_types'].detect do |data|
        ((Regexp.new(data['space_type'].to_s.upcase)).match(sp_type.upcase) || (Regexp.new(sp_type.upcase).match(data['space_type'].to_s.upcase)) || (data['space_type'].to_s.upcase == sp_type.upcase)) and
            data['building_type'].to_s == 'Space Function'
      end
      if sp_type_info.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.thermal_zone_get_centroid_per_floor', "The space type called #{sp_type} could not be found.  Please check that the schedules.json file is available and that the space types are spelled correctly")
        next
      end
      # Determine if space is heated or cooled via spacetype heating or cooling setpoints also checking if the space is
      # a plenum by checking if there is a hvac system associtated with it
      if sp_type_info['heating_setpoint_schedule'].nil? then
        heated = FALSE
      else
        heated = TRUE
      end
      if sp_type_info['cooling_setpoint_schedule'].nil? then
        cooled = FALSE
      else
        cooled = TRUE
      end
      if (sp_type_info['necb_hvac_system_selection_type'] == '- undefined -') || /undefined/.match(sp_type_info['necb_hvac_system_selection_type']) then
        not_plenum = FALSE
      else
        not_plenum = TRUE
      end
      # If the spaces are heated or cooled and are not a plenum then continue
      if (heated || cooled) and not_plenum
        # Get the story name and sit it to none if there is no story name
        story_name = space.buildingStory.get.nameString
        story_name = 'none' if story_name.nil?
        # If this is the first story in the arry then add a new one.
        if stories.empty?
          stories << {
              story_name: story_name,
              spaces: [space],
              centroid: [0, 0, 0],
              ceiling_area: 0
          }
          next
        else
          # If this is not the first story in the array check if the story already is in the array.
          i = nil
          stories.each_with_index do |storycheck, index|
            if storycheck[:story_name] == story_name
              i = index
            end
          end
          # If the story is not in the array then add it.
          if i.nil?
            stories << {
                story_name: story_name,
                spaces: [space],
                centroid: [0, 0, 0],
                ceiling_area: 0
            }
          else
            # If the story is already in the arry then add the space to the array of spaces for that story
            stories[i][:spaces] << space
          end
        end
      end
    end
    # Go through each story in the array above
    stories.each do |story|
      tz_centre = [0, 0, 0, 0]
      # Go through each space in a given story
      story[:spaces].each do |space|
        # Determine the top surface of the space and calculate it's centroid.
        # Get the coordinates of the origin for the space (the coordinates of points in the space are relative to this).
        xOrigin = space.xOrigin
        yOrigin = space.yOrigin
        zOrigin = space.zOrigin
        # Go through each surface in the space and find ceilings by determining which is called 'RoofCeiing'.  Find the
        # overall centroid of all the ceilings in the spaces.  Find centroid by multiplying the centroid of the surfaces
        # multiplied by the area of the surface and add them all up.  Then divide this by the overall area.  This is the
        # area weighted average of the centroid coordinates.
        ceiling_centroid = [0, 0, 0, 0]
        space.surfaces.each do |sp_surface|
          if sp_surface.surfaceType.to_s.upcase == 'ROOFCEILING'
            ceiling_centroid[0] = ceiling_centroid[0] + sp_surface.centroid.x.to_f * sp_surface.grossArea.to_f
            ceiling_centroid[1] = ceiling_centroid[1] + sp_surface.centroid.y.to_f * sp_surface.grossArea.to_f
            ceiling_centroid[2] = ceiling_centroid[2] + sp_surface.centroid.z.to_f * sp_surface.grossArea.to_f
            ceiling_centroid[3] = ceiling_centroid[3] + sp_surface.grossArea
          end
        end

        ceiling_centroid[0] = ceiling_centroid[0] / ceiling_centroid[3]
        ceiling_centroid[1] = ceiling_centroid[1] / ceiling_centroid[3]
        ceiling_centroid[2] = ceiling_centroid[2] / ceiling_centroid[3]

        # This part is used to determine the overall x, y centre of the thermal zone.  This is determined by summing the
        # x and y components times the ceiling area and diving by the total ceiling area.  I also added z since the
        # ceilings may not be all have the same height.
        tz_centre[0] += (ceiling_centroid[0] + xOrigin) * ceiling_centroid[3]
        tz_centre[1] += (ceiling_centroid[1] + yOrigin) * ceiling_centroid[3]
        tz_centre[2] += (ceiling_centroid[2] + zOrigin) * ceiling_centroid[3]
        tz_centre[3] += (ceiling_centroid[3])
      end
      tz_centre[0] /= tz_centre[3]
      tz_centre[1] /= tz_centre[3]
      tz_centre[2] /= tz_centre[3]
      # Update the :centroid and :ceiling_area hashes for the story to reflect the x, y, and z coordinates of the
      # overall centroid of spaces on that floor.
      story[:centroid] = tz_centre[0..2]
      story[:ceiling_area] = tz_centre[3]
    end
    return stories
  end

  #Create a new DX cooling coil with NECB curve characteristics
  def add_onespeed_DX_coil(model, always_on)

    #clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    # clg_cap_f_of_temp = model_add_curve("DXCOOL-NECB2011-REF-CAPFT")
    clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    clg_cap_f_of_temp.setCoefficient1Constant(0.867905)
    clg_cap_f_of_temp.setCoefficient2x(0.0142459)
    clg_cap_f_of_temp.setCoefficient3xPOW2(0.000554364)
    clg_cap_f_of_temp.setCoefficient4y(-0.00755748)
    clg_cap_f_of_temp.setCoefficient5yPOW2(3.3048e-05)
    clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.000191808)
    clg_cap_f_of_temp.setMinimumValueofx(13.0)
    clg_cap_f_of_temp.setMaximumValueofx(24.0)
    clg_cap_f_of_temp.setMinimumValueofy(24.0)
    clg_cap_f_of_temp.setMaximumValueofy(46.0)

    #clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    clg_cap_f_of_flow.setCoefficient1Constant(1.0)
    clg_cap_f_of_flow.setCoefficient2x(0.0)
    clg_cap_f_of_flow.setCoefficient3xPOW2(0.0)
    clg_cap_f_of_flow.setMinimumValueofx(0.0)
    clg_cap_f_of_flow.setMaximumValueofx(1.0)

    # clg_energy_input_ratio_f_of_temp = = model_add_curve(""DXCOOL-NECB2011-REF-COOLEIRFT")
    #clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(0.116936)
    clg_energy_input_ratio_f_of_temp.setCoefficient2x(0.0284933)
    clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(-0.000411156)
    clg_energy_input_ratio_f_of_temp.setCoefficient4y(0.0214108)
    clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.000161028)
    clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.000679104)
    clg_energy_input_ratio_f_of_temp.setMinimumValueofx(13.0)
    clg_energy_input_ratio_f_of_temp.setMaximumValueofx(24.0)
    clg_energy_input_ratio_f_of_temp.setMinimumValueofy(24.0)
    clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.0)

    #clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    # clg_energy_input_ratio_f_of_flow = = model_add_curve("DXCOOL-NECB2011-REF-CAPFFLOW")
    clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.0)
    clg_energy_input_ratio_f_of_flow.setCoefficient2x(0.0)
    clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.0)
    clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.0)
    clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.0)

    # NECB curve modified to take into account how PLF is used in E+, and PLF ranges (> 0.7)
    # clg_part_load_ratio = model_add_curve("DXCOOL-NECB2011-REF-COOLPLFFPLR")
    clg_part_load_ratio = OpenStudio::Model::CurveCubic.new(model)
    clg_part_load_ratio.setCoefficient1Constant(0.0277)
    clg_part_load_ratio.setCoefficient2x(4.9151)
    clg_part_load_ratio.setCoefficient3xPOW2(-8.184)
    clg_part_load_ratio.setCoefficient4xPOW3(4.2702)
    clg_part_load_ratio.setMinimumValueofx(0.7)
    clg_part_load_ratio.setMaximumValueofx(1.0)


    return OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model,
                                                           always_on,
                                                           clg_cap_f_of_temp,
                                                           clg_cap_f_of_flow,
                                                           clg_energy_input_ratio_f_of_temp,
                                                           clg_energy_input_ratio_f_of_flow,
                                                           clg_part_load_ratio);
  end

  # Zonal systems
  def add_zone_baseboards(baseboard_type:,
                          hw_loop:,
                          model:,
                          zone:)
    always_on = model.alwaysOnDiscreteSchedule
    if baseboard_type == 'Electric'
      zone_elec_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(model)
      zone_elec_baseboard.addToThermalZone(zone)
    end
    if baseboard_type == 'Hot Water'
      baseboard_coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(model)
      # Connect baseboard coil to hot water loop
      hw_loop.addDemandBranchForComponent(baseboard_coil)
      zone_baseboard = OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(model, always_on, baseboard_coil)
      # add zone_baseboard to zone
      zone_baseboard.addToThermalZone(zone)
    end
  end


  def add_ptac_dx_cooling(model, zone, zero_outdoor_air)
    # Create a PTAC for each zone:
    # PTAC DX Cooling with electric heating coil; electric heating coil is always off

    # TO DO: need to apply this system to space types:
    # (1) data processing area: control room, data centre
    # when cooling capacity <= 20kW and
    # (2) residential/accommodation: murb, hotel/motel guest room
    # when building/space heated only (this as per NECB; apply to
    # all for initial work? CAN-QUEST limitation)

    # TO DO: PTAC characteristics: sizing, fan schedules, temperature setpoints, interaction with MAU
    always_on = model.alwaysOnDiscreteSchedule
    always_off = BTAP::Resources::Schedules::StandardSchedules::ON_OFF.always_off(model)
    htg_coil = OpenStudio::Model::CoilHeatingElectric.new(model, always_off)

    # Set up PTAC DX coil with NECB performance curve characteristics;
    clg_coil = self.add_onespeed_DX_coil(model, always_on)

    # Set up PTAC constant volume supply fan
    fan = OpenStudio::Model::FanConstantVolume.new(model, always_on)
    fan.setPressureRise(640)

    ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(model,
                                                                         always_on,
                                                                         fan,
                                                                         htg_coil,
                                                                         clg_coil)
    ptac.setName("#{zone.name} PTAC")
    if zero_outdoor_air
      ptac.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded (1.0e-5)
      ptac.setOutdoorAirFlowRateDuringCoolingOperation(1.0e-5)
      ptac.setOutdoorAirFlowRateDuringHeatingOperation(1.0e-5)
    end
    ptac.addToThermalZone(zone)
  end

  def common_air_loop(model:, system_data:)
    mau_air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    mau_air_loop.setName(system_data[:name])
    air_loop_sizing = mau_air_loop.sizingSystem
    air_loop_sizing.autosizeDesignOutdoorAirFlowRate
    air_loop_sizing.setPreheatDesignTemperature(system_data[:PreheatDesignTemperature]) unless system_data[:PreheatDesignTemperature].nil?
    air_loop_sizing.setPreheatDesignHumidityRatio(system_data[:PreheatDesignHumidityRatio]) unless system_data[:PreheatDesignHumidityRatio].nil?
    air_loop_sizing.setPrecoolDesignTemperature(system_data[:PrecoolDesignTemperature]) unless system_data[:PrecoolDesignTemperature].nil?
    air_loop_sizing.setPrecoolDesignHumidityRatio(system_data[:PrecoolDesignHumidityRatio]) unless system_data[:PrecoolDesignHumidityRatio].nil?
    air_loop_sizing.setSizingOption(system_data[:SizingOption] ) unless system_data[:SizingOption].nil?
    air_loop_sizing.setCoolingDesignAirFlowMethod(system_data[:CoolingDesignAirFlowMethod]) unless system_data[:CoolingDesignAirFlowMethod].nil?
    air_loop_sizing.setCoolingDesignAirFlowRate(system_data[:CoolingDesignAirFlowRate]) unless system_data[:CoolingDesignAirFlowRate].nil?
    air_loop_sizing.setHeatingDesignAirFlowMethod(system_data[:HeatingDesignAirFlowMethod]) unless system_data[:HeatingDesignAirFlowMethod].nil?
    air_loop_sizing.setHeatingDesignAirFlowRate(system_data[:HeatingDesignAirFlowRate]) unless system_data[:HeatingDesignAirFlowRate].nil?
    air_loop_sizing.setSystemOutdoorAirMethod(system_data[:SystemOutdoorAirMethod]) unless system_data[:SystemOutdoorAirMethod].nil?
    air_loop_sizing.setCentralCoolingDesignSupplyAirHumidityRatio(system_data[:CentralCoolingDesignSupplyAirHumidityRatio]) unless system_data[:CentralCoolingDesignSupplyAirHumidityRatio].nil?
    air_loop_sizing.setCentralHeatingDesignSupplyAirHumidityRatio(system_data[:CentralHeatingDesignSupplyAirHumidityRatio]) unless system_data[:CentralHeatingDesignSupplyAirHumidityRatio].nil?
    air_loop_sizing.setTypeofLoadtoSizeOn(system_data[:TypeofLoadtoSizeOn]) unless system_data[:TypeofLoadtoSizeOn].nil?
    air_loop_sizing.setCentralCoolingDesignSupplyAirTemperature(system_data[:CentralCoolingDesignSupplyAirTemperature]) unless system_data[:CentralCoolingDesignSupplyAirTemperature].nil?
    air_loop_sizing.setCentralHeatingDesignSupplyAirTemperature(system_data[:CentralHeatingDesignSupplyAirTemperature]) unless system_data[:CentralHeatingDesignSupplyAirTemperature].nil?
    air_loop_sizing.setAllOutdoorAirinCooling(system_data[:AllOutdoorAirinCooling]) unless system_data[:AllOutdoorAirinCooling].nil?
    air_loop_sizing.setAllOutdoorAirinHeating(system_data[:AllOutdoorAirinHeating]) unless system_data[:AllOutdoorAirinHeating].nil?
    air_loop_sizing.setMinimumSystemAirFlowRatio(system_data[:MinimumSystemAirFlowRatio] ) unless system_data[:MinimumSystemAirFlowRatio].nil?
    return mau_air_loop
  end

  def create_heating_cooling_on_off_availability_schedule(model)
    #todo Create a feature to derive start and end heating and cooling seasons from weather file.
    avail_data = [{start_month: 1, start_day: 1, end_month: 6, end_day: 30, htg_value: 1, clg_value: 0},
                  {start_month: 7, start_day: 1, end_month: 10, end_day: 31, htg_value: 0, clg_value: 1},
                  {start_month: 11, start_day: 1, end_month: 12, end_day: 31, htg_value: 1, clg_value: 0}
    ]

    # Heating coil availability schedule for tpfc
    htg_availability_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    htg_availability_sch.setName('tpfc_htg_availability')
    # Cooling coil availability schedule for tpfc
    clg_availability_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    clg_availability_sch.setName('tpfc_clg_availability')
    avail_data.each do |data|
      htg_availability_sch_rule = OpenStudio::Model::ScheduleRule.new(htg_availability_sch)
      htg_availability_sch_rule.setName('tpfc_htg_availability_sch_rule')
      htg_availability_sch_rule.setStartDate(model.getYearDescription.makeDate(data[:start_month], data[:start_day]))
      htg_availability_sch_rule.setEndDate(model.getYearDescription.makeDate(data[:end_month], data[:end_day]))
      htg_availability_sch_rule.setApplySunday(true)
      htg_availability_sch_rule.setApplyMonday(true)
      htg_availability_sch_rule.setApplyTuesday(true)
      htg_availability_sch_rule.setApplyWednesday(true)
      htg_availability_sch_rule.setApplyThursday(true)
      htg_availability_sch_rule.setApplyFriday(true)
      htg_availability_sch_rule.setApplySaturday(true)
      day_schedule = htg_availability_sch_rule.daySchedule
      day_schedule.setName('tpfc_htg_availability_sch_rule_day')
      day_schedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), data[:htg_value])

      clg_availability_sch_rule = OpenStudio::Model::ScheduleRule.new(clg_availability_sch)
      clg_availability_sch_rule.setName('tpfc_clg_availability_sch_rule')
      clg_availability_sch_rule.setStartDate(model.getYearDescription.makeDate(data[:start_month], data[:start_day]))
      clg_availability_sch_rule.setEndDate(model.getYearDescription.makeDate(data[:end_month], data[:end_day]))
      clg_availability_sch_rule.setApplySunday(true)
      clg_availability_sch_rule.setApplyMonday(true)
      clg_availability_sch_rule.setApplyTuesday(true)
      clg_availability_sch_rule.setApplyWednesday(true)
      clg_availability_sch_rule.setApplyThursday(true)
      clg_availability_sch_rule.setApplyFriday(true)
      clg_availability_sch_rule.setApplySaturday(true)
      day_schedule = clg_availability_sch_rule.daySchedule
      day_schedule.setName('tpfc_clg_availability_sch_rule_day')
      day_schedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), data[:clg_value])
    end
    return clg_availability_sch, htg_availability_sch
  end



end
