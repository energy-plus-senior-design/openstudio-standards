
# Custom changes for the RetailStandalone prototype.
# These are changes that are inconsistent with other prototype
# building types.
module RetailStandalone
  # TODO: The ElectricEquipment schedules are wrong in OpenStudio Standards... It needs to be 'RetailStandalone BLDG_EQUIP_SCH' for 90.1-2010 at least but probably all
  # TODO: There is an OpenStudio bug where two heat exchangers are on the equipment list and it references the same single heat exchanger for both. This doubles the heat recovery energy.
  # TODO: The HeatExchangerAirToAir is not calculating correctly. It does not equal the legacy IDF and has higher energy usage due to that.
  # TODO: Need to determine if WaterHeater can be alone or if we need to 'fake' it.

  def model_custom_hvac_tweaks(building_type, climate_zone, prototype_input, model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started building type specific adjustments')

    # Add the door infiltration for template 2004,2007,2010,2013
    case template
    when '90.1-2004'
      entry_space = model.getSpaceByName('Front_Entry').get
      infiltration_entry = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
      infiltration_entry.setName('Entry door Infiltration')
      infiltration_per_zone = 1.418672682
      infiltration_entry.setDesignFlowRate(infiltration_per_zone)
      infiltration_entry.setSchedule(model.add_schedule('RetailStandalone INFIL_Door_Opening_SCH'))
      infiltration_entry.setSpace(entry_space)

      # temporal solution for CZ dependent door infiltration rate.  In fact other standards need similar change as well
    when '90.1-2007', '90.1-2010', '90.1-2013'
      entry_space = model.getSpaceByName('Front_Entry').get
      infiltration_entry = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
      infiltration_entry.setName('Entry door Infiltration')
      case climate_zone
      when 'ASHRAE 169-2006-1A','ASHRAE 169-2006-1B','ASHRAE 169-2006-2A', 'ASHRAE 169-2006-2B'
        infiltration_per_zone = 1.418672682
        infiltration_entry.setSchedule(model.add_schedule('RetailStandalone INFIL_Door_Opening_SCH'))
      else
        infiltration_per_zone = 0.937286742
        infiltration_entry.setSchedule(model.add_schedule('RetailStandalone INFIL_Door_Opening_SCH_2013'))
      end
      infiltration_entry.setDesignFlowRate(infiltration_per_zone)
      infiltration_entry.setSpace(entry_space)
    end

    # add these additional coefficient inputs
    infiltration_entry.setConstantTermCoefficient(1.0)
    infiltration_entry.setTemperatureTermCoefficient(0.0)
    infiltration_entry.setVelocityTermCoefficient(0.0)
    infiltration_entry.setVelocitySquaredTermCoefficient(0.0)

    # Adjust the daylight sensor positions
    update_daylight_sensor_positions(model, climate_zone)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished building type specific adjustments')

    return true
  end

  def update_daylight_sensor_positions(model, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Ajusting daylight sensor positions and fractions')

    adjustments = case climate_zone
    when 'ASHRAE 169-2006-6A', 'ASHRAE 169-2006-6B','ASHRAE 169-2006-7A','ASHRAE 169-2006-8A'
      [
          { 'stds_spc_type' => 'Core_Retail',
            'sensor_1_frac' => 0.1724,
            'sensor_1_xyz' => [14.2, 14.2, 0],
            'sensor_2_frac' => 0.1724,
            'sensor_2_xyz' => [3.4, 14.2, 0]
          }
      ]
    else
      [
          { 'stds_spc_type' => 'Core_Retail',
            'sensor_1_frac' => 0.25,
            'sensor_1_xyz' => [14.2, 14.2, 0],
            'sensor_2_frac' => 0.25,
            'sensor_2_xyz' => [3.4, 14.2, 0]
          }
      ]
    end

    # Adjust daylight sensors in each space
    model.getSpaces.each do |space|
      next if space.thermalZone.emtpy?
      zone = space.thermalZone.get
      next if space.spaceType.empty?
      spc_type = space.spaceType.get
      next if spc_type.standardsSpaceType.empty?
      stds_spc_type = spc_type.standardsSpaceType.get
      adjustments.each do |adj|
        next unless adj['stds_spc_type'] == stds_spc_type
        # Adjust the primary sensor
        if adj['sensor_1_frac']
          zone.setFractionofZoneControlledbyPrimaryDaylightingControl(adj['sensor_1_frac'])
          if zone.primaryDaylightingControl.is_initialized
            pri_ctrl = zone.primaryDaylightingControl.get
            if adj['sensor_1_xyz']
              pri_ctrl.setPositionXCoordinate(adj['sensor_1_xyz'][0])
              pri_ctrl.setPositionYCoordinate(adj['sensor_1_xyz'][1])
              pri_ctrl.setPositionZCoordinate(adj['sensor_1_xyz'][2])
            end
          end
        end
        # Adjust the secondary sensor
        if adj['sensor_2_frac']
          zone.setFractionofZoneControlledbySecondaryDaylightingControl(adj['sensor_2_frac'])
          if zone.secondaryDaylightingControl.is_initialized
            sec_ctrl = zone.secondaryDaylightingControl.get
            if adj['sensor_2_xyz']
              sec_ctrl.setPositionXCoordinate(adj['sensor_2_xyz'][0])
              sec_ctrl.setPositionYCoordinate(adj['sensor_2_xyz'][1])
              sec_ctrl.setPositionZCoordinate(adj['sensor_2_xyz'][2])
            end
          end
        end

      end
    end

    return true
  end

  def update_waterheater_loss_coefficient(model)
    case template
      when '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013', 'NECB2011'
        model.getWaterHeaterMixeds.sort.each do |water_heater|
          water_heater.setOffCycleLossCoefficienttoAmbientTemperature(4.10807252)
          water_heater.setOnCycleLossCoefficienttoAmbientTemperature(4.10807252)
        end
    end
  end

  def model_custom_swh_tweaks(model, building_type, climate_zone, prototype_input)
    update_waterheater_loss_coefficient(model)

    return true
  end
end
