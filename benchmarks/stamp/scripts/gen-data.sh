#!/bin/bash

source scripts.cfg

function usage {

	echo $0' -n <prefix-name> -d <output-dir> [-z <normal-file>] [-y <comp-flv>] [-s <categories>] -c <columns>  [-t <threads>]'

	echo
	echo "-n <prefix-name>: a name to be used as prefix for the output filenames"
	
	echo
	echo "-d <output-dir>: subdirectory to store the generated files "

	echo
	echo "-z <normal-file>: normalize the data to configuration <normal-file>"
	echo "<normal-file> must be a valid file generated by the execute.sh script"
	echo "the path relative to '${_RESULTS}' should be also given"

	echo
	echo "-y <comp-flv>: relative normalization to flavor 'comp-flv'"

	echo
	echo "-s <categories>: subcategories that will be used plot the data"
	echo " Could be <app>, <stm>, <flv>, or <alloc> : the corresponding field in <columns>"
	echo " must be empty"
	echo " Example: -s 'glibc hoard tbbmalloc tcmalloc' -c 'yada:tinySTM:suicide: yada:tinySTM:delay:'"
	echo
	echo " if an item in category is separed by ':' then what follows is the"
	echo " reference file set to be normalized with - each category will be normalized with a different"
	echo " normal file"

	echo
	echo "-c <columns>: columns to plot - format: <app:stm:flv:alloc>"

	echo
	echo "-t <threads>: list with number of threads to be used"
	echo "default = $THREADS"
	


}

function show_using {

	echo "Using:" $1
	echo "  thrs:   $_THREADS" $1
	[ ! -z "$_CATEGORIES" ] && echo "  categories: $_CATEGORIES" $1
}


function validate_normal_file {
	FILENAME="${RESULTDIR}/$1"
	NUMBER=`ls $FILENAME-* | wc -l`
	if [ $NUMBER == "0" ]; then
		echo "$FILENAME does not exist"
		exit 1
	fi
}


function validate_input {

# if not set, use the default configs
	[ -z "$_THREADS" ] && _THREADS=$THREADS

# check if number of threads is a valid numeric value
	for t in $_THREADS; do
		if ! [[ "$t" =~ ^[0-9]+$ ]] ; then
			echo "error: Not a number in -$_THREADS-" 
			exit 1
		fi
	done
		
	show_using >&1
				
	# check if file for normalization exists
	if [ ! -z "$_NORMAL" ]; then
		# -z "all" means to normalize wrt each allocator seq
		if [ "$_NORMAL" != "all" ]; then
			validate_normal_file ${_NORMAL}
		fi
	fi

	# force the following LOOP to be executed at least once
	# this is not elegant, but effective
	[ -z "$_CATEGORIES" ] && _CATEGORIES=" - "
	
	for obj in $_CATEGORIES; do
	# if an item in category is separed by ':' then what follows is the
	# reference file set to be normalized with

		IFS=":"
		tokens=( $obj );
		unset IFS

		obj=${tokens[0]}
		normal=${tokens[1]}
		[ ! -z ${normal} ] && validate_normal_file $normal

		# format <application>:<stmlib>:<flv>:<alloc>
		# for sequential:  <application>:seq::<alloc>
		for col in $_COLUMNS; do

			IFS=":" 
			tokens=( $col );
			unset IFS

			APP=${tokens[0]}
			STM=${tokens[1]}
			FLV=${tokens[2]}
			ALLOC=${tokens[3]}

			[ -z "$APP" ] && APP=$obj
			[ -z "$STM" ] && STM=$obj
			[ -z "$FLV" ] && [ ! "$STM" == "seq" ] && FLV=$obj
			[ -z "$ALLOC" ] && ALLOC=$obj

			for t in $_THREADS; do
				if [ -z "$FLV" ]; then FILENAME=${RESULTDIR}/$STM/$APP/$APP-$STM-$ALLOC
				else
					FILENAME=${RESULTDIR}/${STM}-${FLV}/${APP}/${APP}-${STM}-${FLV}-${ALLOC}-$t
				fi
				NUMBER=`ls $FILENAME-* | wc -l`
				if [ $NUMBER == "0" ]; then
					echo "$FILENAME does not exist"
					exit 1
				fi

			done
	
		done
	done

	if [ ! -f $_GRAPHFILE ]; then
		echo "Graph file not found"
		exit 1
	fi

	# undo
	[ "$_CATEGORIES" == " - " ] && _CATEGORIES=""
}

function mean_ci_R {
	RFILE="tmp2"
R --slave --vanilla --quiet --no-save << RSCRIPT
	data <- read.table("$TEMPFILE", header=TRUE, fill=TRUE)
	sink("${RFILE}")
	
	vx <- data\$Cycles[!is.na(data\$Cycles)]
	myavg <- mean(vx)
	mysd <- sd(vx)
	len <- length(vx)
	error <- qt(0.975,df=len-1)*mysd/sqrt(len)
	perc <- error/myavg*100.0

	if (${NORMVALUE} != 0) {
	  temp <- ${NORMVALUE}/myavg;
	  error <- (error/myavg)*temp;
	  myavg <- temp
	}
	
	vx <- data\$Aborts[!is.na(data\$Aborts)]
	abavg <- mean(vx)
	absd <- sd(vx)
	len <- length(vx)
	aberror <- qt(0.975,df=len-1)*absd/sqrt(len)
	
	vx <- data\$PAPI1[!is.na(data\$PAPI1)]
	p1avg <- mean(vx)
	p1sd <- sd(vx)
	len <- length(vx)
	p1error <- qt(0.975,df=len-1)*p1sd/sqrt(len)
	
	vx <- data\$PAPI2[!is.na(data\$PAPI2)]
	p2avg <- mean(vx)
	p2sd <- sd(vx)
	len <- length(vx)
	p2error <- qt(0.975,df=len-1)*p2sd/sqrt(len)
	
	vx <- data\$PAPI3[!is.na(data\$PAPI3)]
	p3avg <- mean(vx)
	p3sd <- sd(vx)
	len <- length(vx)
	p3error <- qt(0.975,df=len-1)*p3sd/sqrt(len)
	
	vx <- data\$PAPI4[!is.na(data\$PAPI4)]
	p4avg <- mean(vx)
	p4sd <- sd(vx)
	len <- length(vx)
	p4error <- qt(0.975,df=len-1)*p4sd/sqrt(len)

	cat(sprintf("%.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f %.5f", myavg, error, abavg, aberror, p1avg, p1error, p2avg, p2error, p3avg, p3error, p4avg, p4error ))
	sink()
RSCRIPT
}


function get_normal_value {

	NORMVALUE="0"
	if [ ! -z "$1" ]; then
		NORMFILE="${RESULTDIR}/$1"
		TEMPFILE=tmp	
		#echo "Cycles" > $TEMPFILE
		echo "Cycles Aborts PAPI1 PAPI2 PAPI3 PAPI4" > $TEMPFILE
		# R will skip blank lines - so we generate one for invalid log (source) files
		awk 'BEGIN{ counter = 0; last_found = 0} 
			{ if (FNR == 1) { if (last_found != counter) {print " "; last_found=counter;} counter++; } 
		  	  if ($1 == "Time" && $2 == "=") { print $3, "0 0 0 0 0"; last_found++} 
			  else if ($1 == "#txs") { print $5, "0 0 0 0 0"; last_found++}
			} END { if (last_found != counter) print " "}
		' $NORMFILE-* >> $TEMPFILE
		mean_ci_R
		# RFILE is created in 'mean_ci_R'
		NORMVALUE=`cat $RFILE | awk '{print $1}'`
	fi

#	echo $NORMVALUE
}

function generate_data {

	[ ! -d "${TABDIR}" ] && mkdir ${TABDIR}
	OUTPUTDIR="${TABDIR}/${_OUTDIR}"
	[ ! -d "${OUTPUTDIR}" ] && mkdir ${OUTPUTDIR}
	
	OUTPUTFILE="${OUTPUTDIR}/${_PREFIXNAME}.table"
	HEADER="t "
	for col in $_COLUMNS; do
		IFS=":" 
		tokens=( $col );
		unset IFS

		CONF=${tokens[2]}
		ALLOC=${tokens[3]}
		#ALLOC=`echo $ALLOC | sed 's/\([a-z]\)\([a-zA-Z0-9]*\)/\u\1\2/g'`
		#HEADER="$HEADER $col ci"
		HEADER="$HEADER $ALLOC-$CONF ci Abort ci PAPI1 ci PAPI2 ci PAPI3 ci PAPI4 ci"
	done
	#HEADER="t Glibc ci Hoard ci TBBMalloc ci TCMalloc ci"
	echo $HEADER > $OUTPUTFILE
	
	NORMVALUE="0"
	if [ ! -z "$_NORMAL" ]; then
		if [ "$_NORMAL" != "all" ]; then
			get_normal_value ${_NORMAL}
		fi
	fi

	# force the following LOOP to be executed at least once
	# this is not elegant, but effective
	[ -z "$_CATEGORIES" ] && _CATEGORIES=" - "
	
	for obj in $_CATEGORIES; do
		
		IFS=":"
		tokens=( $obj );
		unset IFS

		obj=${tokens[0]}
		normal=${tokens[1]}
		[ ! -z ${normal} ] && get_normal_value $normal

		for t in $_THREADS; do
	
			#echo "$t" >> $OUTPUTFILE
			BUFFER=""
			COLS=0
			for col in $_COLUMNS; do

				IFS=":" 
				tokens=( $col );
				unset IFS

				APP=${tokens[0]}
				STM=${tokens[1]}
				FLV=${tokens[2]}
				ALLOC=${tokens[3]}

				[ -z "$APP" ] && APP=$obj
				[ -z "$STM" ] && STM=$obj
				[ -z "$FLV" ] && [ ! "$STM" == "seq" ] && FLV=$obj
				[ -z "$ALLOC" ] && ALLOC=$obj

				if [ -z "$FLV" ]; then SOURCEFILE=${RESULTDIR}/$STM/${APP}/$APP-$STM-$ALLOC
				else
					SOURCEFILE=${RESULTDIR}/${STM}-${FLV}/${APP}/${APP}-${STM}-${FLV}-${ALLOC}-$t
				fi
          
				if [ ! -z "$_NORMAL" ]; then
					if [ "$_NORMAL" == "all" ]; then
     	  	 				_NORMAL_FILE="seq/${APP}/${APP}-seq-$ALLOC"
						get_normal_value ${_NORMAL_FILE}
					fi	
   				fi 
		
				if [ ! -z "$_COMPFLV" ]; then
				# compares with the provided flavor
					_NORMAL_FILE="${STM}-${_COMPFLV}/${APP}/${APP}-${STM}-${_COMPFLV}-${ALLOC}-$t"
					get_normal_value ${_NORMAL_FILE}
				fi
	
				# if sequential and t > 1, we generate a row with 0's			
				if [ -z "$FLV" -a $t -gt 1 ]; then
					BUFFER="$BUFFER 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0"
				else	
					TEMPFILE=tmp	
					echo "Cycles Aborts PAPI1 PAPI2 PAPI3 PAPI4" > $TEMPFILE
					# R will skip blank lines - so we generate one for invalid log (source) files
					awk 'BEGIN{ counter = 0; last_found = 0; cycles = 0; aborts = 0; papi1 = 0; papi2 = 0; papi3 = 0; papi4 = 0; } 
						{ if (FNR == 1) { 
							if (last_found != counter) {print " "; last_found=counter;} 
							if (cycles != 0) { printf " %.5f %u %u %u %u %u\n", cycles, aborts, papi1, papi2, papi3, papi4 }
							
							counter++;
						        cycles = 0;
							aborts = 0;
							papi1 = 0;
							papi2 = 0;	
						  	papi3 = 0;
							papi4 = 0;
						} 
					  	  
						  # Cycles
						  if ($1 == "Time" && $2 == "=") { cycles=$3; last_found++ } 
				  		  else if ($1 == "#txs") { cycles=$5; last_found++ }
						  # Aborts
						  if ($1 == "#aborts") { aborts=$3; }
						  # PAPI 1
						  #if ($1 == "#accesses/misses:") { papi1 = ($3/$2)*100; } 
						  if ($1 == "#accesses/misses:") { papi1 = $2; papi2 = $3 } 
						  
						  # PAPI 2

						  # PAPI 3
						  if ($1 == "TOTINST:") { papi3 = $2; }
						  # PAPI 4
						  if ($1 == "UREFCYC:") { papi4 = $2; }


						} END { 
						  if (last_found != counter) print " ";
						  #if (cycles != 0) { printf " %.5f %u %2.12f %u %u %u\n", cycles, aborts, papi1, papi2, papi3, papi4 }
						  if (cycles != 0) { printf " %.5f %u %u %u %u %u\n", cycles, aborts, papi1, papi2, papi3, papi4 }
						}
			    		' $SOURCEFILE-* >> $TEMPFILE
		
          				mean_ci_R
					
					# RFILE is created in 'mean_ci_R'
					ROUT=`cat $RFILE`
					BUFFER="$BUFFER $ROUT"
				fi
	

			done
			echo "$t $BUFFER" >> $OUTPUTFILE
			
		done # thread
	done
	
	rm $TEMPFILE
	rm $RFILE
	
}






while getopts "n:d:g:z:s:c:t:y:h" opt;
do
	case $opt in
		n) _PREFIXNAME=$OPTARG ;;
		d) _OUTDIR=$OPTARG ;;
		z) _NORMAL=$OPTARG ;;
		s) _CATEGORIES=$OPTARG ;;
		c) _COLUMNS=$OPTARG ;;
		t) _THREADS=$OPTARG ;;
		y) _COMPFLV=$OPTARG ;;
		h) usage; exit 0 ;;
		\?) usage
			exit 0
	esac
done


if [ -z "$_COLUMNS" ]; then
	echo "argument -c (columns) required"
	exit 1
fi

if [ -z "$_PREFIXNAME" ]; then
	echo "prefix name required"
	usage
	exit 0
fi

validate_input
generate_data
