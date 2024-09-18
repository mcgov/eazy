#! /bin/bash
# author: github.com/mcgov
USAGE_NOTE="$0 : $0 --region westus2 --sku Standard_D96s_v5"
if ! TEMP=$(
	getopt -o 'l:s:F:' \
		--long 'region:,sku:,family:' \
		-n "$0" -- "$@"
); then
	echo "Could not parse args $*" >&2
	exit 1
fi
eval set -- "$TEMP"
unset TEMP
while true; do
	case "$1" in
	'-l' | '--region')
		REGION="$2"
		shift 2
		continue
		;;
	'-s' | '--sku')
		VM_SKU="$2"
		shift 2
		continue
		;;
	'--')
		shift
		break
		;;
	*)
		echo "Unrecognized argument: $1" >&2
		echo "$USAGE_NOTE" >&2
		exit 1
		;;
	esac
done

if [[ -z "$REGION" ]]; then
	echo "Need to supply a region arg with -l / --region "
	exit 1
fi
transform_sku_to_family_size () {
	local SKU=$(echo -n "$1" | awk '{ print tolower($0) }');
	# ex: Standard_d8s_v5
	local SKU_TYPE=$( echo "$SKU" | cut -d '_' -f 1 )
	local FAMILY=$( echo "$SKU" | cut -d '_' -f 2 )
	local VERSION=$( echo "$SKU" | cut -d '_' -f 3 )
	case "$SKU_TYPE" in
		'standard'|'internal'|'experimental')
			SKU_TYPE_LEN=$(echo "$SKU_TYPE" | wc -c )
		;;
		*)
			echo "Unrecognized sku type in $1, expected standard, internal, or experimental." >&2
			return 1
		;;
	esac
	
	# NOTE: assumes single gen id
	local FEATURE_INFO=$(echo -n "$FAMILY" | tr -d '0-9')
	local FAMILY_ID=$(echo "${TYPE_ID}${FEATURE_INFO}${VERSION}" | awk '{ print toupper($0) }')
	local SKU_TYPE=$(echo "${SKU_TYPE}" | awk '{ print tolower($0) }')
	echo "${SKU_TYPE}${FAMILY_ID}Family"
}

get_az_core_quota_for_region() {
	local REGION="$1"
	local VM_SKU="$2"
	local SUBSCRIPTION=$(az account show | jq .id | tr -d '"')
	# get quota for a region
	local FAMILY=$(transform_sku_to_family_size "$VM_SKU")
	QUOTA=$(az quota show   --scope /subscriptions/"$SUBSCRIPTION"/providers/Microsoft.Compute/locations/"$REGION" --resource-name "$FAMILY"  2> /dev/null)
	if [[ -z "$QUOTA" ]]; then
		echo "Could not find quota for family: $FAMILY in region $REGION"
		return 1
	fi
	echo -n "$QUOTA" | jq .properties.limit.value
	return $?
}

get_all_az_core_quota_for_region() {
	local REGION="$1"
	local SUBSCRIPTION=$(az account show | jq .id | tr -d '"')
	# get quota for a region
	COUNT=$(az quota list -o tsv --scope /subscriptions/"$SUBSCRIPTION"/providers/Microsoft.Compute/locations/"$REGION" | cut -f 2 | wc -l)
	JSON_DATA=$(az quota list --scope /subscriptions/"$SUBSCRIPTION"/providers/Microsoft.Compute/locations/"$REGION")
	for i in $(seq 0 $COUNT); do
		LIMIT=$( echo -n "$JSON_DATA" | jq .[$i].properties.limit.value )
		NAME=$( echo -n "$JSON_DATA" | jq .[$i].name | tr -d '"' )
		echo "$NAME : $LIMIT"
	done
 
	return $?
}
if [[ -z "$VM_SKU" ]]; then
	get_all_az_core_quota_for_region "$REGION"
else
	get_az_core_quota_for_region "$REGION" "$VM_SKU"
fi
exit $?
