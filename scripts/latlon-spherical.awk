
BEGIN{_latlon_spherical_init()}

function _latlon_spherical_init() {PI = 4.0*atan2(1.0,1.0); DEG = PI/180.0;}

function to_radians(grad){return grad*DEG}
function to_degrees(rad){return rad/DEG}

#######################################################################################
#  Returns the distance from point1 to point2 (using haversine formula).
# 
#  @param   lat1 - Latitude  of point1.
#  @param   lon1 - Longitude of point1.
#  @param   lat2 - Latitude  of point2.
#  @param   lon2 - Longitude of point2.
#  @param   [radius=6371e3] - (Mean) radius of earth (defaults to radius in metres).
#
#  @returns Distance between point1 and point2, in same units as radius.
# 
#  @example
#      dist = calc_distance(52.205, 0.119, 48.857, 2.351); // 404.3 km
#
function calc_distance(lat1,lon1,lat2,lon2,    radius)
{
  if (length(radius)!=0){R = radius}else{R = 6371e3}
  phi1 = to_radians(lat1); lambda1 = to_radians(lon1);
  phi2 = to_radians(lat2); lambda2 = to_radians(lon2);
  deltaphi = phi2 - phi1;
  deltalambda = lambda2 - lambda1;

  a = sin(deltaphi/2) * sin(deltaphi/2) \
      + cos(phi1) * cos(phi2) \
      * sin(deltalambda/2) * sin(deltalambda/2);
     
  c = 2 * atan2(sqrt(a), sqrt(1-a));
  d = R * c;
  return d;
}


#######################################################################################
# Returns the (initial) bearing from ‘this’ point to destination point.
#
#  @param  lat1 - Latitude  of initial point.
#  @param  lon1 - Longitude of initial point.
#  @param  lat2 - Latitude  of destination point.
#  @param  lon2 - Longitude of destination point.
#
#  @returns Initial bearing in degrees from north.
#
#  @example
#      calc_bearing( 52.205, 0.119, 48.857, 2.351) // 156.2°
#
function calc_bearing(lat1,lon1,lat2,lon2)
{
  phi1 = to_radians(lat1); phi2 = to_radians(lat2);
  deltalambda = to_radians(lon2 - lon1);

  y = sin(deltalambda) * cos(phi2);
  x = cos(phi1)*sin(phi2) - sin(phi1)*cos(phi2)*cos(deltalambda);
  theta = atan2(y,x);

  return (to_degrees(theta)+360) % 360;
}

#/**
# * Returns the (initial) bearing from ‘this’ point to destination point.
# *
# * @param   {LatLon} point - Latitude/longitude of destination point.
# * @returns {number} Initial bearing in degrees from north.
# *
# * @example
# *     var p1 = new LatLon(52.205, 0.119);
# *     var p2 = new LatLon(48.857, 2.351);
# *     var b1 = p1.bearingTo(p2); // 156.2°
# */
#LatLon.prototype.bearingTo = function(point) {
#    if (!(point instanceof LatLon)) throw new TypeError('point is not LatLon object');
#
#    var φ1 = this.lat.toRadians(), φ2 = point.lat.toRadians();
#    var Δλ = (point.lon-this.lon).toRadians();
#
#    // see http://mathforum.org/library/drmath/view/55417.html
#    var y = Math.sin(Δλ) * Math.cos(φ2);
#    var x = Math.cos(φ1)*Math.sin(φ2) -
#            Math.sin(φ1)*Math.cos(φ2)*Math.cos(Δλ);
#    var θ = Math.atan2(y, x);
#
#    return (θ.toDegrees()+360) % 360;
#};


