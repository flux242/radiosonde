
BEGIN{_latlon_spherical_init()}

function _latlon_spherical_init() {PI = 4.0*atan2(1.0,1.0); DEG = PI/180.0;}

function asin(x) { return atan2(x,sqrt(1-x*x)) }
function acos(x) { return atan2(sqrt(1-x*x),x) }
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
#  Returns the (initial) bearing from ‘this’ point to destination point.
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

#######################################################################################
#  Returns the point of intersection of two paths defined by point and bearing
#
#  @param  lat1 - Latitude  of first point.
#  @param  lon1 - Longitude of first point.
#  @param  bearing1 - Initial bearing from first point.
#  @param  lat2 - Latitude  of first point.
#  @param  lon2 - Longitude of first point.
#  @param  bearing2 - Initial bearing from first point.
#
#  @returns Intersection point (null if no unique intersection defined).
#
#  @example
#
#     calc_intersection(51.8853, 0.2545, 108.547, 49.0034, 2.5735, 32.435) // 50.9078°N, 004
#
function calc_intersection(lat1, lon1, bearing1, lat2, lon2, bearing2)
{
  p1[1] = to_radians(lat1); p1[2] = to_radians(lon1); p1[3] = to_radians(bearing1);
  p2[1] = to_radians(lat2); p2[2] = to_radians(lon2); p2[3] = to_radians(bearing2);

  dlat=p2[1]-p1[1];
  dlon=p2[2]-p1[2];
  delta12=2*asin(sqrt(sin(dlat/2)*sin(dlat/2) + cos(p1[1])*cos(p2[1])*sin(dlon/2)*sin(dlon/2)));
  if (delta12 == 0.0) exit 1

  thetaA= acos( (sin(p2[1]) - sin(p1[1])*cos(delta12))/(sin(delta12)*cos(p1[1])) );
  thetaB= acos( (sin(p1[1]) - sin(p2[1])*cos(delta12))/(sin(delta12)*cos(p2[1])) );

  if (sin(p2[2]-p1[2]) > 0.0) {
    theta12 = thetaA;
    theta21 = 2*PI - thetaB;
  }
  else {
    theta12 = 2*PI - thetaA;
    theta21 = thetaB;
  }

  alpha1 = (p1[3] - theta12 + PI) % (2*PI) - PI;
  alpha2 = (theta21 - p2[3] + PI) % (2*PI) - PI;


  if (sin(alpha1)==0 && sin(alpha2)==0.0) return;  # infinite intersections
  if (sin(alpha1)*sin(alpha2) < 0.0) return;       # ambiguous intersection

  alpha3 = acos( -1*cos(alpha1)*cos(alpha2) + sin(alpha1)*sin(alpha2)*cos(delta12) );
  delta13 = atan2( sin(delta12)*sin(alpha1)*sin(alpha2), cos(alpha2) + cos(alpha1)*cos(alpha3) );

  lat3 = asin( sin(p1[1])*cos(delta13) + cos(p1[1])*sin(delta13)*cos(p1[3]) );

  dlon13 = atan2( sin(p1[3])*sin(delta13)*cos(p1[1]), cos(delta13) - sin(p1[1])*sin(lat3) );
  lon3 = p1[2] + dlon13;

  print to_degrees(lat3)" "(to_degrees(lon3)+540)%360 - 180;
}

