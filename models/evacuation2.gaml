/***
* Name: Evacuation2
* Author: xuan quy
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model Evacuation

global {
		
	// Time step to represent very short term movement (for congestion)
	float step <- 10#sec;
	
	int nb_of_people;
	
	// To initialize perception distance of inhabitant
	float min_perception_distance <- 10.0;
	float max_perception_distance <- 30.0;
	
	// Parameters of the strategy
	int time_after_last_stage;
	string the_alert_strategy;
	int nb_stages;
	
	// Parameters of hazard
	int time_before_hazard;
	float flood_front_speed;
	
	file road_file <- file("../includes/roads.shp");
//	file buildings <- file("../includes/buildings.shp");
//	file buildings <- file("../includes/building house 3.shp");
	file water_buildings <- file("../includes/water in buildings.shp");
	file buildings <- file("../includes/building house 4.shp");
	file green_buildings <- file("../includes/green building.shp");
//	file water_body <- file("../includes/broken.shp");
	file embankments <- file("../includes/embankment.shp");
	file evac_points <- file("../includes/point evacuation 2 gb.shp");
	file water_body <- file("../includes/river.shp");
	file naturals <- file("../includes/naturals.shp");
	geometry shape <- envelope(envelope(buildings)+envelope(water_body));

	// Graph road
	graph road_network;
	
	// Output the number of casualties
	int casualties;
	
	init {
 		create building from: buildings with:[id::int(read("id"))];

        create natural from: naturals ;
        create embankment from: embankments ;
		create road from:road_file;
		create evacuation_point from:evac_points;
		create hazard from: water_body;

		create green_building from: green_buildings with:[id::int(read("id"))];
		list<green_building> id_buildings <- green_building where (each.id=0);

		create inhabitant number:nb_of_people/10 {
			location <-any_location_in(one_of(id_buildings));
			safety_point <- any(evacuation_point);
			perception_distance <- rnd(min_perception_distance, max_perception_distance);
		}
		
		create crisis_manager;
		
		road_network <- as_edge_graph(road);
	
	}
	
	// Stop the simulation when everyone is either saved :) or dead :(
	reflex stop_simu when:inhabitant all_match (each.saved or each.drowned) {
		do pause;
	}
//	reflex stop_simu when:(any(evacuation_point) overlaps any(hazard)) {
//			do pause;
//	}
	
	
}



species natural {
    string type; 
    rgb color <- #blue  ;
    
    aspect base {
    draw shape color: color ;
    }
}

species embankment {
    string type; 
    rgb color <- #orange  ;
    
    aspect base {
    draw shape color: color ;
    }
}

species green_building {
    string type; 
	int height;
	int id; 
    rgb color <- #yellow  ;
    
    aspect base {
    draw shape color: color ;
    }
}
/*
 * Agent responsible of the communication strategy
 */
species crisis_manager {
	
	/*
	 * Time between each alert stage (#s)
	 */
	float alert_range;
	
	/*
	 * The number of people to alert every stage
	 */
	int nb_per_stage;
	

	
	init {
		// For stage strategy
		int modulo_stage <- length(inhabitant) mod nb_stages; 
		nb_per_stage <- int(length(inhabitant) / nb_stages) + (modulo_stage = 0 ? 0 : 1);
		
		alert_range <- (time_before_hazard#mn - time_after_last_stage#mn) / nb_stages;

	}
	
	/*
	 * If the crisis manager should send an alert
	 */
	reflex send_alert when: alert_conditional() {
		ask alert_target() { self.alerted <- true; }
	}
	
	/*
	 * The conditions to send an alert : return true at cycle = 0 and then every(alert_range)
	 * depending on the strategy used
	 */
	bool alert_conditional {
		if(the_alert_strategy = "STAGED" or the_alert_strategy = "SPATIAL"){
			return every(alert_range);
		} else {
			if(cycle = 0){
				return true;
			} else {
				return false;
			}
		}
	}
	
	/*
	 * Who to send the alert to: return a list of inhabitant according to the strategy used
	 */
	list<inhabitant> alert_target {
		switch the_alert_strategy {
			match "STAGED" {
				return nb_per_stage among (inhabitant where (each.alerted = false));
			}
			match "EVERYONE" {
				return list(inhabitant);
			}
			default {
				return [];
			}
		}
	}
	
}

/*
 * Represent the water body. When attribute triggered is turn to true, inhabitant
 * start to see water as a potential danger, and try to escape
 */
species hazard {
	
	bool stoped;
		
	// The date of the hazard
	date catastrophe_date;
	
	// Is it a tsunami ? (or just a little regular wave)
	bool triggered;
	
	init {
		catastrophe_date <- current_date + time_before_hazard#mn;
	}
	
	/*
	 * The shape the represent the water expend every cycle to mimic a (big) wave
	 */
	reflex expand when:(catastrophe_date < current_date) {
		if(not(triggered)) {triggered <- true;}
		if(not(stoped)){
			shape <- shape buffer (flood_front_speed#m/#mn * step) intersection world;
		}
//		if(any(embankment) overlaps self){
//			stoped <- true;
//		}
	}
	
	aspect default {
		draw shape color:#blue;
	}

}

/*
 * Represent the inhabitant of the area. They move at foot. They can pereive the hazard or be alerted
 * and then will try to reach the one randomly choose exit point
 */
species inhabitant skills:[moving] {
	
	// The state of the agent
	bool alerted <- false;
	bool drowned <- false;
	bool saved <- false;
	
	// How far (#m) they can perceive
	float perception_distance;
	
	// The exit point they choose to reach
	evacuation_point safety_point;
	// How fast inhabitant can run
	float speed <- 10#km/#h;
	
	/*
	 * Am I drowning ?
	 */
	reflex drown when:not(drowned or saved) {
		if(first(hazard) covers self){
//			write ("die");
			drowned <- true;
			casualties <- casualties + 1; 
		}
	}
	
	/*
	 * Is there any danger around ?
	 */
	reflex perceive when: not(alerted or drowned) and first(hazard).triggered {
		if self.location distance_to first(hazard).shape < perception_distance {
			alerted <- true;
		}
	}
	
	/*
	 * When alerted people will try to go to the choosen exit point
	 */
	reflex evacuate when:alerted and not(drowned or saved) {
		do goto target:safety_point on: road_network;
		if(current_edge != nil){
			road the_current_road <- road(current_edge);  
			the_current_road.users <- the_current_road.users + 1;
		}
	}
	
	/*
	 * Am I safe ?
	 */
	reflex escape when: not(saved) and location distance_to safety_point < 2#m{
		saved <- true;
		alerted <- false;
	}
	
	aspect default {
		draw drowned ? cross(4,0.2) : circle(1#m) color:drowned ? #black : (alerted ? #red : #green);
	}
	
}

/*
 * The point of evacuation
 */
species evacuation_point {
	
	int count_exit <- 0 update: length((inhabitant where each.saved) at_distance 4#m);
		
	aspect default {
		draw circle(1#m+49#m*count_exit/nb_of_people) color:#green;
	}
	
}

/*
 * The roads inhabitant will use to evacuate. Roads compute the congestion of road segment
 * accordin to the Underwood function.
 */
species road {
	
	// Number of user on the road section
	int users;
	// The capacity of the road section
	int capacity <- int(shape.perimeter);
	// The Underwood coefficient of congestion
	float speed_coeff <- 1.0;
	
	// Cut the road when flooded so people cannot use it anymore
	reflex flood_road {
		if(hazard first_with (each covers self) != nil){
			road_network >- self; 
			do die;
		}
	}
	
	aspect default{
		draw shape width: 4#m-(3*speed_coeff)#m color:rgb(55+200*users/capacity,0,0);
	}	
	
}

/*
 * People are located in building at the start of the simulation
 */
species building {
	string type; 
	int height;
	int id;
	aspect default {
		draw shape color: #gray border: #black;
	}
}

experiment "Run" {
//	float minimum_cycle_duration <- 0.1;
		
	parameter "Alert Strategy" var:the_alert_strategy init:"STAGED" among:["NONE","STAGED","EVERYONE"] category:"Alert";
	parameter "Number of stages" var:nb_stages init:6 category:"Alert";
	parameter "Time alert buffer before hazard" var:time_after_last_stage init:5 unit:#mn category:"Alert";
	parameter "Speed of the flood front" var:flood_front_speed init:5.0 min:1.0 max:30.0 unit:#m/#mn category:"Hazard";
	parameter "Time before hazard" var:time_before_hazard init:10 min:0 max:100 unit:#mn category:"Hazard";
	
	parameter "Number of people" var:nb_of_people init:24550 min:1000 max:50000 category:"Initialization";
	
	output {
		display my_display type:opengl{ 
			species evacuation_point;
			species road;
			species hazard;
			
			species green_building;
			species building;
			species inhabitant;
			species natural;
//			species embankment;
			graphics "my new layer" { 
      			draw "Number of casualties: " + casualties*10 at: {10,-50} size: 20 color: #black font: font('Default', 12, #bold) ; 
   			} 
		}
//		monitor "Number of casualties" value:casualties*10;
	}	
	
}



