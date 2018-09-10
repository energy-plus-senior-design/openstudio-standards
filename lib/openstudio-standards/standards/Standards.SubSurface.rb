class Standard
  # @!group SubSurface

  # Determine the component infiltration rate for this surface
  #
  # @param type [String] choices are 'baseline' and 'advanced'
  # @return [Double] infiltration rate
  #   @units cubic meters per second (m^3/s)
  def sub_surface_component_infiltration_rate(sub_surface, type)
    comp_infil_rate_m3_per_s = 0.0

    # Define the envelope component infiltration rates
    component_infil_rates_cfm_per_ft2 = {
      'baseline' => {
        'opaque_door' => 0.40,
        'loading_dock_door' => 0.40,
        'swinging_or_revolving_glass_door' => 1.0,
        'vestibule' => 1.0,
        'sliding_glass_door' => 0.40,
        'window' => 0.40,
        'skylight' => 0.40
      },
      'advanced' => {
        'opaque_door' => 0.20,
        'loading_dock_door' => 0.20,
        'swinging_or_revolving_glass_door' => 1.0,
        'vestibule' => 1.0,
        'sliding_glass_door' => 0.20,
        'window' => 0.20,
        'skylight' => 0.20
      }
    }

    boundary_condition = sub_surface.outsideBoundaryCondition
    # Skip non-outdoor surfaces
    return comp_infil_rate_m3_per_s unless outsideBoundaryCondition == 'Outdoors' || sub_surface.outsideBoundaryCondition == 'Ground'

    # Per area infiltration rate for this surface
    surface_type = sub_surface.subSurfaceType
    infil_rate_cfm_per_ft2 = nil
    case boundary_condition
    when 'Outdoors'
      case surface_type
      when 'Door'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['opaque_door']
      when 'OverheadDoor'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['loading_dock_door']
      when 'GlassDoor'
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.Standards.Model', "For #{sub_surface.name}, assuming swinging_or_revolving_glass_door for infiltration calculation.")
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['swinging_or_revolving_glass_door']
      when 'FixedWindow', 'OperableWindow'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['window']
      when 'Skylight', 'TubularDaylightDome', 'TubularDaylightDiffuser'
        infil_rate_cfm_per_ft2 = component_infil_rates_cfm_per_ft2[type]['skylight']
      end
    end
    if infil_rate_cfm_per_ft2.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Standards.Model', "For #{sub_surface.name}, could not determine surface type for infiltration, will not be included in calculation.")
      return comp_infil_rate_m3_per_s
    end

    # Area of the surface
    area_m2 = sub_surface.netArea
    area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

    # Rate for this surface
    comp_infil_rate_cfm = area_ft2 * infil_rate_cfm_per_ft2

    comp_infil_rate_m3_per_s = OpenStudio.convert(comp_infil_rate_cfm, 'cfm', 'm^3/s').get

    # OpenStudio::logFree(OpenStudio::Debug, "openstudio.Standards.Model", "......#{self.name}, infil = #{comp_infil_rate_cfm.round(2)} cfm @ rate = #{infil_rate_cfm_per_ft2} cfm/ft2, area = #{area_ft2.round} ft2.")

    return comp_infil_rate_m3_per_s
  end

  # Reduce the area of the subsurface by shrinking it
  # toward the centroid.
  # @author Julien Marrec
  #
  # @param percent_reduction [Double] the fractional amount
  # to reduce the area.
  def sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(sub_surface, percent_reduction)
    mult = 1 - percent_reduction
    scale_factor = mult**0.5

    # Get the centroid (Point3d)
    g = sub_surface.centroid

    # Create an array to collect the new vertices
    new_vertices = []

    # Loop on vertices (Point3ds)
    sub_surface.vertices.each do |vertex|
      # Point3d - Point3d = Vector3d
      # Vector from centroid to vertex (GA, GB, GC, etc)
      centroid_vector = vertex - g

      # Resize the vector (done in place) according to scale_factor
      centroid_vector.setLength(centroid_vector.length * scale_factor)

      # Move the vertex toward the centroid
      vertex = g + centroid_vector

      new_vertices << vertex
    end

    # Assign the new vertices to the self
    sub_surface.setVertices(new_vertices)
  end

  # Reduce the area of the subsurface by raising the
  # sill height.
  #
  # @param percent_reduction [Double] the fractional amount
  # to reduce the area.
  def sub_surface_reduce_area_by_percent_by_raising_sill(sub_surface, percent_reduction)
    mult = 1 - percent_reduction

    # Calculate the original area
    area_original = sub_surface.netArea

    # Find the min and max z values
    min_z_val = 99_999
    max_z_val = -99_999
    sub_surface.vertices.each do |vertex|
      # Min z value
      if vertex.z < min_z_val
        min_z_val = vertex.z
      end
      # Max z value
      if vertex.z > max_z_val
        max_z_val = vertex.z
      end
    end

    # Calculate the window height
    height = max_z_val - min_z_val

    # Calculate the new sill height
    new_sill_z = max_z_val - (height * mult)

    # Reset the z value of the lowest points
    new_vertices = []
    sub_surface.vertices.each do |vertex|
      new_x = vertex.x
      new_y = vertex.y
      new_z = vertex.z
      if new_z == min_z_val
        new_z = new_sill_z
      end
      new_vertices << OpenStudio::Point3d.new(new_x, new_y, new_z)
    end

    # Reset the vertices
    sub_surface.setVertices(new_vertices)

    return true
  end

  # Determine if the sub surface is a vertical rectangle,
  # meaning a rectangle where the bottom is parallel to the ground.
  def sub_surface_vertical_rectangle?(sub_surface)
    # Get the vertices once
    verts = sub_surface.vertices

    # Check for 4 vertices
    return false unless verts.size == 4

    # Check if the 2 lowest z-values
    # are the same
    z_vals = []
    verts.each do |vertex|
      z_vals << vertex.z
    end
    z_vals = z_vals.sort
    return false unless z_vals[0] == z_vals[1]

    # Check if the diagonals are equal length
    diag_a = verts[0] - verts[2]
    diag_b = verts[1] - verts[3]
    return false unless diag_a.length == diag_b.length

    # If here, we have a rectangle
    return true
  end

  def sub_surface_create_centered_subsurface_from_scaled_surface(surface, area_fraction, model)
    sub_const = nil
    surf_cent = surface.centroid
    scale_factor = Math.sqrt(area_fraction)

    # Create an array to collect the new vertices
    new_vertices = []

    # Loop on vertices (Point3ds)
    surface.vertices.each do |vertex|
      # Point3d - Point3d = Vector3d
      # Vector from centroid to vertex (GA, GB, GC, etc)
      centroid_vector = vertex - surf_cent

      # Resize the vector (done in place) according to scale_factor
      centroid_vector.setLength(centroid_vector.length * scale_factor)

      # Move the vertex toward the centroid
      new_vertex = surf_cent + centroid_vector

      new_vertices << new_vertex
    end
    new_sub_surface = OpenStudio::Model::SubSurface.new(new_vertices, model)
    new_sub_surface.setSurface(surface)
    new_name = surface.name.to_s + '_' + new_sub_surface.subSurfaceType.to_s
    new_sub_surface.setName(new_name)
    new_sub_surface.setMultiplier(1)
  end

  def set_Window_To_Wall_Ratio_set_name(surface, area_fraction)
    surface.setWindowToWallRatio(area_fraction)
    surface.subSurfaces.sort.each do |sub_surf|
      new_name = surface.name.to_s + '_' + sub_surf.subSurfaceType.to_s
      sub_surf.setName(new_name)
    end
  end
end
