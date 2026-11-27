import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

export function driverProtectionFeeAt(at: Date) {
  if (!Number.isFinite(at.getTime())) throw Error('Invalid quote time');
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: 'America/Belize', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(at);
  const hour = Number(parts.find(p => p.type === 'hour')!.value);
  const minute = Number(parts.find(p => p.type === 'minute')!.value);
  return hour * 60 + minute >= 20 * 60 + 45 ? 3 : 0;
}
export function calculateSwiftRideFare(miles: number, pickupMiles = 0, returnMiles = 0, at = new Date()) {
  if (![miles, pickupMiles, returnMiles].every(x => Number.isFinite(x) && x >= 0)) throw Error('Invalid road distance');
  const cents = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
  const standardFare = cents(5 + Math.ceil(Math.max(0, miles - 0.75) / 0.25 - 1e-9) * 0.75);
  const pickupSupplement = 0;
  const returnAllowance = cents(returnMiles * 0.50);
  const subtotal = cents(standardFare + pickupSupplement + returnAllowance);
  const roundedSubtotal = subtotal;
  const driverProtectionFee = driverProtectionFeeAt(at);
  const customerTotal = cents(roundedSubtotal + driverProtectionFee);
  const roundingAdjustment = cents(roundedSubtotal - subtotal);
  return { standardFare, pickupSupplement, returnAllowance, roundingAdjustment, driverProtectionFee, customerTotal, requiresConfirmation: false, currency: 'BZD' };
}

type Point = {lat: number; lng: number};
export function inZone(p: Point, polygon: Point[]) {
  let inside = false;
  for (let i=0,j=polygon.length-1;i<polygon.length;j=i++) {
    const a=polygon[i],b=polygon[j];
    if (((a.lat>p.lat)!==(b.lat>p.lat)) && p.lng<(b.lng-a.lng)*(p.lat-a.lat)/(b.lat-a.lat)+a.lng) inside=!inside;
  }
  return inside;
}
function decodePolyline(encoded: string): Point[] {
  const points: Point[]=[];let i=0,lat=0,lng=0;
  function delta(){let value=0,shift=0,byte;do{if(i>=encoded.length)throw Error('Invalid return route');byte=encoded.charCodeAt(i++)-63;value|=(byte&31)<<shift;shift+=5;}while(byte>=32);return value&1?~(value>>1):value>>1;}
  while(i<encoded.length){lat+=delta();lng+=delta();points.push({lat:lat/1e5,lng:lng/1e5});}return points;
}
export function zoneEntry(path: Point[], polygon: Point[]): Point | null {
  if (!path.length) return null;
  if (inZone(path[0],polygon)) return path[0];
  for(let k=1;k<path.length;k++){
    const a=path[k-1],b=path[k];let best=Infinity;
    for(let i=0;i<polygon.length;i++){
      const c=polygon[i],d=polygon[(i+1)%polygon.length];
      const rx=b.lng-a.lng,ry=b.lat-a.lat,sx=d.lng-c.lng,sy=d.lat-c.lat;
      const denominator=rx*sy-ry*sx;if(Math.abs(denominator)<1e-15)continue;
      const t=((c.lng-a.lng)*sy-(c.lat-a.lat)*sx)/denominator;
      const u=((c.lng-a.lng)*ry-(c.lat-a.lat)*rx)/denominator;
      if(t>=0&&t<=1&&u>=0&&u<=1)best=Math.min(best,t);
    }
    if(Number.isFinite(best))return {lat:a.lat+(b.lat-a.lat)*best,lng:a.lng+(b.lng-a.lng)*best};
  }return null;
}
async function returnRoadMiles(destination: Point, zone: {polygon: Point[]; return_anchor: Point}) {
  if(inZone(destination,zone.polygon))return 0;
  if(!inZone(zone.return_anchor,zone.polygon))throw Error('The return-route anchor must be inside the service zone.');
  const route=await roadRoute(destination,zone.return_anchor,true);
  const path=decodePolyline(route.polyline?.encodedPolyline||'');
  const entry=zoneEntry(path,zone.polygon);
  if(!entry)throw Error('Could not determine the road entry to the service zone.');
  // Route to the road/boundary intersection; never charge a straight-line distance.
  return await roadMiles(destination,entry);
}

async function roadRoute(a: Point, b: Point, withPath = false) {
  const apiKey = Deno.env.get('GOOGLE_ROUTES_API_KEY')?.trim();
  if (!apiKey) throw Error('Routing setup: GOOGLE_ROUTES_API_KEY is missing in Supabase Edge Function Secrets.');
  if (a.lat === b.lat && a.lng === b.lng) return { distanceMeters: 0 };
  const waypoint = (p: typeof a) => ({ location: { latLng: { latitude: p.lat, longitude: p.lng } } });
  const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
    method: 'POST', signal: AbortSignal.timeout(12000),
    headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': apiKey, 'X-Goog-FieldMask': withPath ? 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline' : 'routes.distanceMeters,routes.duration' },
    body: JSON.stringify({ origin: waypoint(a), destination: waypoint(b), travelMode: 'DRIVE', routingPreference: 'TRAFFIC_UNAWARE', computeAlternativeRoutes: false })
  });
  const result = await response.json();
  if (!response.ok) {
    const status = result.error?.status || response.status;
    const reason = String(result.error?.message || 'Google rejected the routing request.').split(apiKey).join('[redacted]');
    console.error('Google Routes error', { status, reason });
    throw Error('Google Routes (' + status + '): ' + reason);
  }
  if (!result.routes?.length) throw Error('No driving route found. Move the pickup and destination pins onto accessible roads.');
  const meters = result.routes[0].distanceMeters ?? 0;
  if (!Number.isFinite(meters) || meters < 0) throw Error('Google returned an invalid road distance. Please try again.');
  return result.routes[0];
}
async function roadMiles(a: Point,b: Point){
  const route=await roadRoute(a,b);return (route.distanceMeters??0)/1609.344;
}

async function pickupRoutes(drivers: any[], pickup: Point) {
  const apiKey=Deno.env.get('GOOGLE_ROUTES_API_KEY')?.trim();
  if(!apiKey)throw Error('Routing setup: GOOGLE_ROUTES_API_KEY is missing.');
  const waypoint=(lat:number,lng:number)=>({location:{latLng:{latitude:lat,longitude:lng}}});
  const ranked:any[]=[];
  // One destination per batch avoids making a separate HTTP request for each driver.
  for(let start=0;start<drivers.length;start+=50){
    const batch=drivers.slice(start,start+50);
    const response=await fetch('https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix',{
      method:'POST',signal:AbortSignal.timeout(15000),
      headers:{'Content-Type':'application/json','X-Goog-Api-Key':apiKey,'X-Goog-FieldMask':'originIndex,destinationIndex,status,condition,distanceMeters,duration'},
      body:JSON.stringify({origins:batch.map(d=>({waypoint:waypoint(Number(d.lat),Number(d.lng))})),destinations:[{waypoint:waypoint(pickup.lat,pickup.lng)}],travelMode:'DRIVE',routingPreference:'TRAFFIC_UNAWARE'})
    });
    const elements=await response.json();
    if(!response.ok||!Array.isArray(elements))throw Error('Pickup arrival estimates are unavailable. Please try again.');
    for(const element of elements){
      const driver=batch[element.originIndex??0];
      if(!driver||(element.destinationIndex??0)!==0||element.status?.code||element.condition!=='ROUTE_EXISTS')continue;
      const meters=Number(element.distanceMeters??0);
      const seconds=element.duration==null&&meters===0?0:Number(String(element.duration).replace(/s$/,''));
      if(!Number.isFinite(meters)||meters<0||!Number.isFinite(seconds)||seconds<0)continue;
      ranked.push({driver,distance:meters/1609.344,pickupMinutes:Math.ceil(seconds/60)});
    }
  }
  return ranked.sort((a,b)=>a.distance-b.distance||a.pickupMinutes-b.pickupMinutes||String(a.driver.driver_id).localeCompare(String(b.driver.driver_id)));
}

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'POST required' }, 405);
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const authorization = req.headers.get('Authorization') || '';
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } } });
    const jwt=authorization.replace(/^Bearer\s+/i,'').trim();
    if(!jwt)return reply({error:'Sign in before getting a fare.'},401);
    const { data: { user }, error: authError } = await userClient.auth.getUser(jwt);
    if (authError || !user) return reply({ error: 'Sign in before getting a fare.' }, 401);
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    const input = await req.json();
    if(input.trackingRideId){
      const {data: ride,error}=await userClient.rpc('swiftride_current',{p_id:input.trackingRideId});
      if(error||!ride) return reply({error:'Ride tracking unavailable'},403);
      const fresh=ride.location_fresh&&ride.lat!=null&&ride.lng!=null&&Date.now()-Date.parse(ride.location_updated_at)<90000;
      if(!fresh||!['accepted','en_route','arrived'].includes(ride.status))return reply({locationFresh:false,pickupMinutes:null});
      const routes=await pickupRoutes([{driver_id:ride.driver_id,lat:Number(ride.lat),lng:Number(ride.lng)}],{lat:Number(ride.pickup_lat),lng:Number(ride.pickup_lng)});
      return reply({locationFresh:true,pickupMinutes:routes[0]?.pickupMinutes??null,pickupMiles:routes[0]?.distance??null,locationUpdatedAt:ride.location_updated_at});
    }
    const b = input.booking;
    if (!b) throw Error('Choose pickup and destination.');
    for (const key of ['p_pickup_lat','p_pickup_lng','p_dropoff_lat','p_dropoff_lng']) {
      const value = b[key];
      if (typeof value !== 'number' || !Number.isFinite(value) || Math.abs(value) > (key.endsWith('lat') ? 90 : 180)) throw Error('Invalid location');
    }
    for (const [key, max] of [['p_name',100],['p_phone',30],['p_pickup',250],['p_dropoff',250]] as const) {
      if (typeof b[key] !== 'string' || (!b[key].trim() && key !== 'p_name' && key !== 'p_phone') || b[key].length > max) throw Error('Complete your contact and location details.');
    }
    // Fleet authorization and online preference come from the server, never customer-supplied GPS.
    const { data: fleet, error: fleetError } = await userClient.rpc('swiftride_fleet', { p_lat: b.p_pickup_lat, p_lng: b.p_pickup_lng, p_radius_km: null });
    if (fleetError) throw Error(fleetError.message);
    const pickup = { lat: b.p_pickup_lat, lng: b.p_pickup_lng };
    const {data: zone,error: zoneError}=await admin.from('swiftride_service_zone').select('polygon,return_anchor').eq('id',1).maybeSingle();
    if(zoneError)throw Error('Install SwiftRide-balanced-pilot.sql before quoting fares.');
    if(!zone)throw Error('Set the Orange Walk service zone in the admin portal before quoting fares.');
    const returnMiles=await returnRoadMiles({lat:b.p_dropoff_lat,lng:b.p_dropoff_lng},zone);
    const tripRoute = await roadRoute(pickup, { lat: b.p_dropoff_lat, lng: b.p_dropoff_lng });
    const miles = (tripRoute.distanceMeters ?? 0)/1609.344;
    const tripSeconds = Number(String(tripRoute.duration || '0s').replace(/s$/,''));
    const tripMinutes = Number.isFinite(tripSeconds) && tripSeconds>0 ? Math.ceil(tripSeconds/60) : null;
    const available = (fleet || []).filter((d: any) => Number.isFinite(Date.parse(d.location_updated_at)) && d.lat != null && d.lng != null && Number.isFinite(Number(d.lat)) && Number.isFinite(Number(d.lng)));
    if (!available.length) return reply({ noDriver: true, standardFare: calculateSwiftRideFare(miles).standardFare, roadMiles: miles, currency: 'BZD' });
    // Compare road routes, not straight-line distance. Only a verified pickup route can win.
    const ranked = await pickupRoutes(available,pickup);
    if (!ranked.length) throw Error('Pickup road distances unavailable. Please try again.');
    const quoteTime=new Date();
    const prepared=ranked.map(({driver,distance:pickupMiles,pickupMinutes})=>({driver,pickupMiles,pickupMinutes,fare:calculateSwiftRideFare(miles,pickupMiles,returnMiles,quoteTime)}));
    const { data: quotes, error } = await admin.from('swiftride_pricing_quotes').insert(prepared.map(({driver,pickupMiles,fare})=>({
      customer_id: user.id, driver_id: driver.driver_id, booking: b, road_miles: miles, pickup_miles: pickupMiles,
      standard_fare: fare.standardFare, pickup_supplement: fare.pickupSupplement, requires_confirmation: fare.requiresConfirmation, return_miles: returnMiles, return_allowance: fare.returnAllowance, rounding_adjustment: fare.roundingAdjustment, driver_protection_fee: fare.driverProtectionFee
    }))).select('id,driver_id,expires_at,driver_protection_fee');
    if (error) throw Error(error.message);
    // Database time is authoritative, including a quote that crosses 20:45 while routing.
    const options=prepared.map(({driver,pickupMiles,pickupMinutes,fare})=>{
      const quote=quotes?.find((q:any)=>q.driver_id===driver.driver_id);
      if(!quote)throw Error('A ride quote was not saved. Please try again.');
      const driverProtectionFee=Number(quote.driver_protection_fee);
      if(![0,3].includes(driverProtectionFee))throw Error('Invalid Driver Protection Fee');
      const customerTotal=Math.round((fare.customerTotal-fare.driverProtectionFee+driverProtectionFee)*100)/100;
      const locationAge=Date.now()-Date.parse(driver.location_updated_at);
      return {...fare,driverName:driver.display_name||'Verified driver',driverId:driver.driver_id,vehicleModel:driver.vehicle_model||null,serviceName:'Swift ONE',tripMinutes,driverProtectionFee,customerTotal,quoteId:quote.id,expiresAt:quote.expires_at,roadMiles:miles,pickupMiles,returnMiles,pickupMinutes,locationFresh:driver.location_fresh!==false&&locationAge>=0&&locationAge<90000,locationUpdatedAt:driver.location_updated_at,vehicleType:driver.vehicle_type==='motorcycle'?'motorcycle':'car',passengerSeats:driver.passenger_seats};
    });
    // Keep the closest quote at the top level for already-installed APKs.
    return reply({...options[0],driverName:prepared[0].driver.display_name,options});
  } catch (e) { return reply({ error: e instanceof Error ? e.message : 'Could not calculate fare' }, 400); }
});


