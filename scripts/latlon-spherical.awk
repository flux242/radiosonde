
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
#  Returns the (initial) bearing from point1 to point2.
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
#        calc_intersection(51.8853, 0.2545, 108.547, 49.0034, 2.5735, 32.435) // 50.9078°N, 004.5084°E
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

  return to_degrees(lat3)";"(to_degrees(lon3)+540)%360 - 180;
}



#######################################################################################
#  Returns the destination point from input point having travelled the given distance on the
#  given initial bearing (bearing normally varies around path followed).
#
#  @param  lat1 - Latitude  of first point.
#  @param  lon1 - Longitude of first point.
#  @param  bearing1 - Initial bearing from first point.
#  @param  distance - distance to the destination point in meters.
#  @param  radius - Optional (Mean) radius of earth in meters (defaults to 6371e3).
#
#  @returns Destination Point lat and lon.
#
#  @example
#
#        destination_point(51.4778, -0.0015, 300.7, 7794) // 51.5135°N, 000.0983°W
#
function destination_point(lat1, lon1, bearing1, distance,    radius)
{
  if (length(radius)!=0){R = radius}else{R = 6371e3}
  # sinφ2 = sinφ1⋅cosδ + cosφ1⋅sinδ⋅cosθ
  # tanΔλ = sinθ⋅sinδ⋅cosφ1 / cosδ−sinφ1⋅sinφ2
  # see http://williams.best.vwh.net/avform.htm#LL

  delta = distance / R; # angular distance in radians
  theta = to_radians(bearing1);

  phi1 = to_radians(lat1);
  lambda1 = to_radians(lon1);

  sinPhi1 = sin(phi1); cosPhi1 = cos(phi1);
  sinDelta = sin(delta); cosDelta = cos(delta);
  sinTheta = sin(theta); cosTheta = cos(theta);


  sinPhi2 = sinPhi1*cosDelta + cosPhi1*sinDelta*cosTheta;
  phi2 = asin(sinPhi2);
  y = sinTheta * sinDelta * cosPhi1;
  x = cosDelta - sinPhi1 * sinPhi2;
  lambda2 = lambda1 + atan2(y, x);

  return to_degrees(phi2)";"(to_degrees(lambda2)+540)%360 - 180; # normalise to −180..+180°
}

function lla2ecef(lat,lon,alt)
{
  # WGS84 ellipsoid constants:
  a = 6378137;
  e = 8.1819190842622e-2;
  lat=to_radians(lat);
  lon=to_radians(lon);
  # intermediate calculation
  # (prime vertical radius of curvature)
  N = a / sqrt(1 - e*e * sin(lat)*sin(lat));
  x = (N+alt) * cos(lat) * cos(lon);
  y = (N+alt) * cos(lat) * sin(lon);
  z = ((1-e*e) * N + alt) * sin(lat);

  return x" "y" "z
}

# Converts the Earth-Centered Earth-Fixed (ECEF) coordinates (x, y, z) to
# East-North-Up coordinates in a Local Tangent Plane that is centered at the
# (WGS-84) Geodetic point (lat0, lon0, alt0).
function ecef2enu(x, y, z, lat0,lon0,alt0)
{
  e = 8.1819190842622e-2;
  lambda = to_radians(lat0);
  phi = to_radians(lon0);
  s = sin(lambda);
  N = a / sqrt(1 - e*e * s * s);

  sin_lambda = sin(lambda);
  cos_lambda = cos(lambda);
  cos_phi = cos(phi);
  sin_phi = sin(phi);

  x0 = (alt0 + N) * cos_lambda * cos_phi;
  y0 = (alt0 + N) * cos_lambda * sin_phi;
  z0 = (alt0 + (1 - e*e) * N) * sin_lambda;

  xd = x - x0;
  yd = y - y0;
  zd = z - z0;

  # This is the matrix multiplication
  xEast = -sin_phi * xd + cos_phi * yd;
  yNorth = -cos_phi * sin_lambda * xd - sin_lambda * sin_phi * yd + cos_lambda * zd;
  zUp = cos_lambda * cos_phi * xd + cos_lambda * sin_phi * yd + sin_lambda * zd;

  return xEast" "yNorth" "zUp
}

function lla2enu(lat, lon, alt, lat0,lon0,alt0)
{
  ecefstr=lla2ecef(lat,lon,alt);
  n1=split(ecefstr,p1," ");
  if (n1!=3) return;

  return ecef2enu(p1[1],p1[2],p1[3], lat0, lon0, alt0)
}

###############################################################################
# Converts the Earth-Centered Earth-Fixed (ECEF) coordinates (x, y, z) in meters
# to lat lon alt. WGS-84 model is used
#
#  ----Test 1---------
# Inputs:   -576793.17, -5376363.47, 3372298.51
# Expected: 32.12345, -96.12345, 500.0
# awk -i ./latlon-spherical.awk 'BEGIN{print ecef2lla(-576793.17, -5376363.47, 3372298.51)}'
# 32.1235 -96.1235 499.998
# Actuals:  32.12345004807767, -96.12345000213524, 499.997958839871
#-----Test 2---------
# Inputs:   2297292.91, 1016894.94, -5843939.62
# Expected: -66.87654, 23.87654, 1000.0
# awk -i ./latlon-spherical.awk 'BEGIN{print ecef2lla(2297292.91, 1016894.94, -5843939.62)}'
# -66.8765 23.8765 999.998
#Actuals:  -66.87654001741278, 23.87653991401422, 999.9983866894618
function ecef2lla(x, y, z)
{
  # WGS84 ellipsoid constants
  a = 6378137; # radius
  e = 8.1819190842622e-2; # eccentricity

  asq = a^2;
  esq = e^2;

  b   = sqrt( asq * (1-esq) );
  bsq = b^2;
  ep  = sqrt( (asq - bsq)/bsq );
  p   = sqrt( x^2 + y^2 );
  th  = atan2(a*z, b*p);

  lon = atan2(y,x);
  lat = atan2( (z + ep^2*b*sin(th)^3 ), (p - esq*a*cos(th)^3) );
  N = a / sqrt(1-esq*sin(lat)^2);
  alt = p / cos(lat) - N;

  # mod lat to 0-2pi
  lon = lon % (2*PI);

  # correction for altitude near poles left out.

  return to_degrees(lat)" "to_degrees(lon)" "alt;
}
