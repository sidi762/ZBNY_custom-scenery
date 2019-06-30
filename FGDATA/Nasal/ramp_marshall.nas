var enableRampMarshall = getprop("/sim/enable-ramp-marshall");

if(enableRampMarshall == nil) {
	setprop("/sim/enable-ramp-marshall", 1); # Enabled by default
}

var closestAirport = func() {
	return getprop("/sim/airport/closest-airport-id");
};

var ramp_pos = geo.Coord.new();

var M2NM = 0.0005399568;
var NM2M = 1852;

var ramp_dist = getprop("/sim/model/ramp/x-m");
var ramp_class = getprop("/sim/model/ramp/class");
if (ramp_dist == nil) {
ramp_dist = -14;
}
if (ramp_class == nil) {
ramp_class = 3;
}

# RAMP CLASS CODES
## 0 - 747, 777-300, A340, A380
## 1 - A330-300, 777-200
## 2 - A330-200, 787
## 3 - A320, 737, General

var ramp_classes = [0,0.5,0.85,1.72];

ramp_dist = -(ramp_dist - ramp_classes[ramp_class]);

# Mathematical Heading Operations
var addHdg = func(hdg, add) {
	var result = hdg + add;
	if(result>360) {
		result = result - 360;
	}
	return result;
}

var subHdg = func(hdg, diff) {
	var result = hdg - diff;
	if(result<0) {
		result = 360 - result;
	}
	return result;
}

var getDeviation = func(hdg, target) {
	var deviation = target - hdg;
	if(deviation < -180) {
		deviation = 360 - deviation;
	} elsif(deviation > 180) {
		deviation = deviation - 360;
	}
	return deviation;
}

# Smooth Property Animation
var animate = func(prop, target, rate) { # Rate is in deg/sec
	
	var delta_sec = getprop("/sim/time/delta-sec");
	if(rate == nil) {
		rate = 50;
	}
	if(delta_sec == nil) {
		delta_sec = 0.1;
	}
	
	var value = getprop(prop);
	if(value != nil) {
		if(math.abs(value-target) > rate*delta_sec) {
			if(value < target) {
				setprop(prop, value + rate*delta_sec);
			} else {
				setprop(prop, value - rate*delta_sec);
			}
		} else {
			if(value != target) {
				setprop(prop, target);
			}
		}
	}
	
};

# Marshaller Hand Positions

var rmPos = {
	lA_x: 0,
	lA_y: 0,
	lA_z: 0,
	lAO_x: 0,
	lH_x: 0,
	lH_y: 0,
	lH_z: 0,
	rA_x: 0,
	lA_y: 0,
	rA_z: 0,
	rAO_x: 0,
	rH_x: 0,
	rH_y: 0,
	rH_z: 0,
	new: func(lA_x=0, lA_y=0, lA_z=0, lAO_x=0, lH_x=0, lH_y=0, lH_z=0, rA_x=0, rA_y=0, rA_z=0, rAO_x=0, rH_x=0, rH_y=0, rH_z=0) {
		var m = { parents: [rmPos] };
		m.lA_x = lA_x;
		m.lA_y = lA_y;
		m.lA_z = lA_z;
		m.lAO_x = lAO_x;
		m.lH_x = lH_x;
		m.lH_y = lH_y;
		m.lH_z = lH_z;
		m.rA_x = rA_x;
		m.rA_y = rA_y;
		m.rA_z = rA_z;
		m.rAO_x = rAO_x;
		m.rH_x = rH_x;
		m.rH_y = rH_y;
		m.rH_z = rH_z;
		return m;
	}
};

var pos = {};

var anim = {};

var propValue = func(child, node) { # If it's empty, return 0 as value
	var value = child.getNode(node, 1).getValue();
	if(value == nil) {
		return 0;
	} else {
		return value;
	}
}

var load_signals = func() {
	var filename = getprop("/sim/fg-root")~"/Models/Airport/Ramp/signals.xml";
	io.read_properties(filename, "/airports/ramp-marshall/");
	
	var positions = props.globals.getNode("/airports/ramp-marshall/positions");	
	
	foreach(var position; positions.getChildren()) {
		if(position.getNode("name").getValue() != nil) {
			pos[position.getNode("name").getValue()] = rmPos.new(
				lA_x: propValue(position, "left-arm-x"),
				lA_y: propValue(position, "left-arm-y"),
				lA_z: propValue(position, "left-arm-z"),
				lAO_x: propValue(position, "left-arm-outer-x"),
				lH_x: propValue(position, "left-hand-x"),
				lH_x: propValue(position, "left-hand-y"),
				lH_x: propValue(position, "left-hand-z"),
				rA_x: propValue(position, "right-arm-x"),
				rA_y: propValue(position, "right-arm-y"),
				rA_z: propValue(position, "right-arm-z"),
				rAO_x: propValue(position, "right-arm-outer-x"),
				rH_x: propValue(position, "right-hand-x"),
				rH_x: propValue(position, "right-hand-y"),
				rH_x: propValue(position, "right-hand-z")
			);
		}
	}
	
	var signals = props.globals.getNode("/airports/ramp-marshall/signals");
	
	foreach(var signal; signals.getChildren()) {
		if(signal.getNode("name").getValue() != nil) {
			var signalName = signal.getNode("name").getValue();
			if(signal.getNode("type").getValue() == "steps") {
				anim[signalName] = [];
				var steps = signal.getNode("steps");
				foreach(var step; steps.getChildren()) {
					if(step.getNode("action").getValue() == "animate") {
						# Animate Marshall to position
						append(anim[signalName], [step.getNode("position").getValue(), step.getNode("speed").getValue()]);
					} elsif(step.getNode("action").getValue() == "hold-pos") {
						append(anim[signalName], nil);
					} elsif(step.getNode("action").getValue() == "jump-to") {
						append(anim[signalName], step.getNode("step").getValue());
					} elsif(step.getNode("action").getValue() == "wait-time") {
						append(anim[signalName], ['wait-time', step.getNode("time-sec").getValue()]);
					} elsif(step.getNode("action").getValue() == "wait-cond") {
						append(anim[signalName], ['wait-cond', step.getNode("condition").getPath()]);
					}
				}
			} else {
				var script = signal.getNode("script",1).getValue();
				if(script == nil) {
					anim[signalName] = ['nasal', func() { print("Empty Script - make sure you're using the CDATA tags"); }];
				} else {
					anim[signalName] = ['nasal', compile(script)];
				}
			}
		}
	}
	
	
}

# Return current position values
var get_pos_values = func(ramp_tree) {
	
	return rmPos.new(
		getprop(ramp_tree~"left-arm-x"),
		getprop(ramp_tree~"left-arm-y"),
		getprop(ramp_tree~"left-arm-z"),
		getprop(ramp_tree~"left-arm-outer-x"),
		getprop(ramp_tree~"left-hand-x"),
		getprop(ramp_tree~"left-hand-y"),
		getprop(ramp_tree~"left-hand-z"),
		getprop(ramp_tree~"right-arm-x"),
		getprop(ramp_tree~"right-arm-y"),
		getprop(ramp_tree~"right-arm-z"),
		getprop(ramp_tree~"right-arm-outer-x"),
		getprop(ramp_tree~"right-hand-x"),
		getprop(ramp_tree~"right-hand-y"),
		getprop(ramp_tree~"right-hand-z")
	);

};

var check_pos = func(ramp_tree, target) {

	var position = get_pos_values(ramp_tree);
	
	if(
		(position.lA_x == target.lA_x) and
		(position.lA_y == target.lA_y) and
		(position.lA_z == target.lA_z) and
		(position.lAO_x == target.lAO_x) and
		(position.lH_x == target.lH_x) and
		(position.lH_y == target.lH_y) and
		(position.lH_z == target.lH_z) and
		(position.rA_x == target.rA_x) and
		(position.rA_y == target.rA_y) and
		(position.rA_z == target.rA_z) and
		(position.rAO_x == target.rAO_x) and
		(position.rH_x == target.rH_x) and
		(position.rH_y == target.rH_y) and
		(position.rH_z == target.rH_z)
	) {
		return 1;
	} else {
		return 0;
	}

};

var full_animate = func(ramp_tree, pos_hash, rate) {
	animate(ramp_tree~"left-arm-x",pos_hash.lA_x , rate);
	animate(ramp_tree~"left-arm-y",pos_hash.lA_y , rate);
	animate(ramp_tree~"left-arm-z",pos_hash.lA_z , rate);
	animate(ramp_tree~"left-arm-outer-x",pos_hash.lAO_x , rate);
	animate(ramp_tree~"left-hand-x",pos_hash.lH_x , rate);
	animate(ramp_tree~"left-hand-y",pos_hash.lH_y , rate);
	animate(ramp_tree~"left-hand-z",pos_hash.lH_z , rate);
	animate(ramp_tree~"right-arm-x",pos_hash.rA_x , rate);
	animate(ramp_tree~"right-arm-y",pos_hash.rA_y , rate);
	animate(ramp_tree~"right-arm-z",pos_hash.rA_z , rate);
	animate(ramp_tree~"right-arm-outer-x",pos_hash.rAO_x , rate);
	animate(ramp_tree~"right-hand-x",pos_hash.rH_x , rate);
	animate(ramp_tree~"right-hand-y",pos_hash.rH_y , rate);
	animate(ramp_tree~"right-hand-z",pos_hash.rH_z , rate);
};

var addModel = func(path, lat, lon, alt, hdg) {

	# Derived from jetways.nas

	var models = props.globals.getNode("/models");
	var model = nil;
	for(var i=0; 1; i+=1) {
		if(models.getChild("model", i, 0) == nil) {
			model = models.getChild("model", i, 1);
			break;
		}
	}
	
	var model_path = model.getPath();
	model.getNode("path", 1).setValue(path);
	model.getNode("latitude-deg", 1).setDoubleValue(lat);
	model.getNode("latitude-deg-prop", 1).setValue(model_path ~ "/latitude-deg");
	model.getNode("longitude-deg", 1).setDoubleValue(lon);
	model.getNode("longitude-deg-prop", 1).setValue(model_path ~ "/longitude-deg");
	model.getNode("elevation-ft", 1).setDoubleValue(alt * M2FT);
	model.getNode("elevation-ft-prop", 1).setValue(model_path ~ "/elevation-ft");
	model.getNode("heading-deg", 1).setDoubleValue(hdg);
	model.getNode("heading-deg-prop", 1).setValue(model_path ~ "/heading-deg");
	model.getNode("pitch-deg", 1).setDoubleValue(0);
	model.getNode("pitch-deg-prop", 1).setValue(model_path ~ "/pitch-deg");
	model.getNode("roll-deg", 1).setDoubleValue(0);
	model.getNode("roll-deg-prop", 1).setValue(model_path ~ "/roll-deg");
	model.getNode("load", 1).remove();
	return model;

};

var load_ramps = func(icao) {

	var xml_file = getprop("/sim/fg-root") ~ "/AI/Airports/" ~ icao ~ "/ramps.xml";
	
	var rampsTree = "/airports/"~icao~"/ramps";
	
	readFile = io.read_properties(xml_file, rampsTree);
	if(readFile == nil) {
	
		return;
	
	} else {
	
		setprop(rampsTree~"/loaded", 1); # Set Loaded flag so flightgear doesn't load again
	
		print("Loaded Ramps at " ~ icao);
	
		var ramps = props.globals.getNode(rampsTree).getChildren();
	
		foreach(var ramp; ramps) {
			# General Runtime XML
			var index = ramp.getIndex();
			var base_model = getprop("/sim/fg-root") ~ "/Models/Airport/Ramp/ramp.xml";

			var tmp = props.globals.getNode(rampsTree~"/models/model", 1);
			tmp.getNode("path", 1).setValue(base_model);
		
			var tree = rampsTree ~ "/ramp[" ~ index ~ "]/";
		
			setprop(tree~"left-arm-x", 80);
			setprop(tree~"left-arm-y", 0);
			setprop(tree~"left-arm-z", 0);
			setprop(tree~"left-arm-outer-x", 0);
			setprop(tree~"left-hand-x", 0);
			setprop(tree~"left-hand-y", 0);
			setprop(tree~"left-hand-z", 0);
			setprop(tree~"right-arm-x", -80);
			setprop(tree~"right-arm-y", 0);
			setprop(tree~"right-arm-z", 0);
			setprop(tree~"right-arm-outer-x", 0);
			setprop(tree~"right-hand-x", 0);
			setprop(tree~"right-hand-y", 0);
			setprop(tree~"right-hand-z", 0);
			setprop(tree~"function", "rest");
		
			var params = tmp.getNode("overlay", 1).getNode("params", 1);
			params.getNode("left-arm-x", 1).setValue(tree~"left-arm-x");
			params.getNode("left-arm-y", 1).setValue(tree~"left-arm-y");
			params.getNode("left-arm-outer-x", 1).setValue(tree~"left-arm-outer-x");
			params.getNode("left-arm-z", 1).setValue(tree~"left-arm-z");
			params.getNode("left-hand-x", 1).setValue(tree~"left-hand-x");
			params.getNode("left-hand-y", 1).setValue(tree~"left-hand-y");
			params.getNode("left-hand-z", 1).setValue(tree~"left-hand-z");
			params.getNode("right-arm-x", 1).setValue(tree~"right-arm-x");
			params.getNode("right-arm-y", 1).setValue(tree~"right-arm-y");
			params.getNode("right-arm-outer-x", 1).setValue(tree~"right-arm-outer-x");
			params.getNode("right-arm-z", 1).setValue(tree~"right-arm-z");
			params.getNode("right-hand-x", 1).setValue(tree~"right-hand-x");
			params.getNode("right-hand-y", 1).setValue(tree~"right-hand-y");
			params.getNode("right-hand-z", 1).setValue(tree~"right-hand-z");
			params.getNode("toggle-ramp-marshall-script", 1).setValue("ramp_marshall.toggle_marshall(" ~ index ~ ");");
		
			var model_path = getprop("/sim/fg-home") ~ "/state/ramp-" ~ index ~ ".xml";
		
			io.write_properties(model_path, rampsTree~"/models");
		
			var ramp_path = rampsTree ~ "/ramp[" ~ index ~ "]/";
		
			# Add model to FlightGear
			addModel(model_path, getprop(ramp_path~"latitude-deg"), getprop(ramp_path~"longitude-deg"), getprop(ramp_path~"altitude-m"), getprop(ramp_path~"heading-deg"));
		}
	
	}

};

var toggle_marshall = func(id) {

	var activeRamp = getprop("/airports/active-ramp");
	var rampEnable = getprop("/airports/enable-ramp");
	
	if(rampEnable == 0) {
		var ramp_dat = "/airports/"~closestAirport()~"/ramps/ramp["~id~"]/";
		ramp_pos.set_latlon(getprop(ramp_dat~"latitude-deg"), getprop(ramp_dat~"longitude-deg"));
		setprop("/airports/active-ramp", id);
		setprop("/airports/enable-ramp", 1);
	} else {
		if(activeRamp == id) {
		setprop("/airports/enable-ramp", 0); # Disable Ramp
		} else {
			var ramp_dat = "/airports/"~closestAirport()~"/ramps/ramp["~id~"]/";
			ramp_pos.set_latlon(getprop(ramp_dat~"latitude-deg"), getprop(ramp_dat~"longitude-deg"));
			setprop("/airports/active-ramp", id);
		}
	}

};

# Main Loop
var main_loop = {
   init : func {
		me.UPDATE_INTERVAL = 0.01;
		print("Initialized Ramp Marshall Script");
		me.function = getprop("rest");
		me.calcFunc = 1;
		load_signals();
		setprop("/airports/active-arpt", closestAirport());
		setprop("/airports/active-ramp", 0);
		setprop("/airports/enable-ramp", 0);
		me.timer = 0;
		me.phase = 0;
		me.loopid = 0;
		me.reset();
},
	update : func {
	
	if(getprop("/sim/enable-ramp-marshall") == 1) {
	
		# Check if ramps are loaded at the nearest airport
	
		if(getprop( "/airports/"~closestAirport()~"/ramps/loaded") == nil) {
			load_ramps(closestAirport());
			setprop("/airports/active-arpt", closestAirport());
		}
	
		var activeRamp = getprop("/airports/active-ramp");
	
		var ramp_tree = "/airports/"~closestAirport()~"/ramps/ramp["~activeRamp~"]/";
	
		# If a ramp is enabled, run the function to guide the pilot
	
		if(getprop("/airports/enable-ramp") == 1) {
	
			if(me.function != getprop(ramp_tree~"function")) {
				me.function = getprop(ramp_tree~"function");
				me.phase = 0;
			}
			
			if(me.calcFunc == 1) {
		
				var ac_pos = geo.aircraft_position();
				var heading = getprop("/orientation/heading-deg");
	
				var ngear = ac_pos;	
				ngear.apply_course_distance(heading, ramp_dist*M2NM);
	
				var dist_to_ramp = ngear.distance_to(ramp_pos);
	
				setprop(ramp_tree~"dist-ramp", dist_to_ramp);
	
				var taxi_course = ngear.course_to(ramp_pos);
	
				var deviation = getDeviation(heading, taxi_course);
	
				setprop(ramp_tree~"deviation", deviation);
	
				if(math.abs(deviation) > 150) {
					setprop(ramp_tree~"function", "imm_stop");
				} elsif(deviation > 1) {
					setprop(ramp_tree~"function", "turn_right");
				} elsif(deviation < -1) {
					setprop(ramp_tree~"function", "turn_left");
				} else {
					if(dist_to_ramp > ramp_dist + 2) {
						setprop(ramp_tree~"function", "move_fwd");
					} elsif(dist_to_ramp > ramp_dist + 0.3) {
						setprop(ramp_tree~"function", "slow_stop");
					} else {
						setprop(ramp_tree~"function", "imm_stop");
					}
		
				}
				
			}
	
	
			# Ramp Marshall Signals	
	
			if(contains(anim,me.function)) {
				if(anim[me.function][0] == 'nasal') {
					anim[me.function][1]();
				} else {
					if(me.phase != nil) {
						if(me.phase >= size(anim[me.function])) me.phase = 0;
						var a = anim[me.function][me.phase];
						if(typeof(a) == 'scalar') {
							me.phase = a;
							if(me.phase != nil) a = anim[me.function][me.phase];
						}
						if(me.phase != nil and a != nil) {
							setprop("/airports/ramp-marshall-phase", me.phase);
							if(a[0] == 'wait-time') {
								if(me.timer < a[1]) {
									me.timer += getprop("/sim/time/delta-sec");
								} else {
									me.phase += 1;
									me.timer = 0;
								}
							} elsif(a[0] == 'wait-cond') {
								if(props.condition(a[1])) {
									me.phase += 1;
								}
							} else {
								# Action is animate		
								if(check_pos(ramp_tree, pos[a[0]])) {
									me.phase += 1;
								} else {
									full_animate(ramp_tree, pos[a[0]], a[1]);
								}
							}
						}
					}
				}
			} # If function is unknown, it is in testing mode
		
		} else { # Return to rest position
	
			full_animate(ramp_tree, rmPos.new(lA_x:80, rA_x:-80), 80);
	
		}
		
	}
	
},

	reset : func {
		me.loopid += 1;
		me._loop_(me.loopid);
},
	_loop_ : func(id) {
		id == me.loopid or return;
		me.update();
		settimer(func { me._loop_(id); }, me.UPDATE_INTERVAL);
}

};

setlistener("sim/signals/fdm-initialized", func() {
main_loop.init();
});

# Editor/Converter

var filedlg = 0;

var posData = {
	lat: 0,
	lon: 0,
	alt: 0,
	hdg: 0,		
	new: func(lat, lon, alt, hdg) {
	
		var m = { parents: [posData] };
		m.lat = lat;
		m.lon = lon;
		m.alt = alt;
		m.hdg = hdg;
		
		return m;
	
	}
};

var rampPos = [];

var convert_stg = func() {

	setprop("/sim/gui/dialogs/file-select/show-files", 1);
	fgcommand("dialog-show", props.Node.new({ "dialog-name": "file-select" }));
	setprop("/sim/gui/dialogs/file-select/path", "");
	
	filedlg = setlistener("/sim/gui/dialogs/file-select/path", func(n) {
	
		removelistener(filedlg);
		var path = n.getValue();
		if (path == "") return;
		var stg = io.open(path, mode="r");
		var n = 0;
		while(var stg_line = io.readln(stg)) {
		
			var line_data = split(" ", stg_line);
			
			if(substr(line_data[0],0,1) != "#") { # Comment Line
			
				if((line_data[0] == "OBJECT_SHARED") and (line_data[1] == "Models/Airport/Ramp/ramp.xml")) { # Valid Ramp Model
				
					append(rampPos, posData.new(line_data[3], line_data[2], line_data[4], line_data[5]));
				
				}
			
			}
		
		}
		
		for(var i=0; i<size(rampPos); i+=1) {
		
			setprop("/airports/export/ramps/ramp["~i~"]/latitude-deg", rampPos[i].lat);
			setprop("/airports/export/ramps/ramp["~i~"]/longitude-deg", rampPos[i].lon);
			setprop("/airports/export/ramps/ramp["~i~"]/altitude-m", rampPos[i].alt);
			setprop("/airports/export/ramps/ramp["~i~"]/heading-deg", geo.normdeg(360 - rampPos[i].hdg));
			
		}
		
		var location = "/airports/export/ramps/";
		var filename = getprop("/sim/fg-home") ~ "/Export/ramps-export.xml";
		
		io.write_properties(filename, location);
		
		print("Converted to STG");
	
	});

};
