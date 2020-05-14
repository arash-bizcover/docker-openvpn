#!/bin/bash
set -o pipefail

readarray -t lines < $1 || echo "❌ OKTA AUTH FAIL: coudn't read the user pass file at $1"
OKTA_USER=${lines[0]}
c2=${lines[1]}


 ######  ##     ## ########  ######  ##    ##  ######
##    ## ##     ## ##       ##    ## ##   ##  ##    ##
##       ##     ## ##       ##       ##  ##   ##
##       ######### ######   ##       #####     ######
##       ##     ## ##       ##       ##  ##         ##
##    ## ##     ## ##       ##    ## ##   ##  ##    ##
 ######  ##     ## ########  ######  ##    ##  ######

for check in OKTA_HOST OKTA_TOKEN APP_ID OKTA_USER c2; do
    if [[ -z $(eval echo -n "\$$(echo $check)") ]]; then
        echo -n "❌ OKTA AUTH FAIL: Variable $check is not set"
        echo
        exit 1
    fi
done


######## ##     ## ##    ##  ######   ######
##       ##     ## ###   ## ##    ## ##    ##
##       ##     ## ####  ## ##       ##
######   ##     ## ## ## ## ##        ######
##       ##     ## ##  #### ##             ##
##       ##     ## ##   ### ##    ## ##    ##
##        #######  ##    ##  ######   ######

login(){
    #Login user with Okta and get ID
    USER=`curl -s -X POST -H "Accept: application/json" -H "Content-Type: application/json" -d "{\"username\":\"$1\",\"password\":\"$2\",\"options\":{\"multiOptionalFactorEnroll\":true,\"warnBeforePasswordExpired\":false}}" $OKTA_HOST/api/v1/authn`

    if [[ `echo -e $USER | jq -r '.status'` -eq "SUCCESS" ]]; then
        USER_ID=`echo -e $USER | jq -r '._embedded.user.id' `
        echo -e "`date` ✅ $1 User login ID is: $USER_ID"
    else 
        echo -e "`date` ❌ $1 failed login:\n$USER"
        exit 1
    fi
}

assignment_check(){
    #Check User association
    ASSIGNMENT=`curl -s -L -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: SSWS $OKTA_TOKEN" "$OKTA_HOST/api/v1/apps/$1/users"`

    if [[ `echo -e $ASSIGNMENT | jq -r ".[].credentials.userName | select(.==\"$OKTA_USER\")"` ]]; then
        echo -e "`date` $OKTA_USER   Application is assigned to the User"
    else 
        echo -e "`date` $OKTA_USER ❌ Application is not assigned to the User"
        exit 1
    fi

}

mfapush() { 
    #GET MFA push associated with the user
    MFA_PUSH=`echo $1 | jq -r '[.[] | select((.status=="ACTIVE") and .factorType=="push" )][0]'`
    MFA_PUSH_ID=`echo $MFA_PUSH | jq -r '.id'`
    if [[ -n $MFA_PUSH_ID ]] ; then
        echo -e "`date` $OKTA_USER  MFA PUSH ID is: $MFA_PUSH_ID"
        MFA_PUSH_LINK=`echo $MFA_PUSH | jq -r ' ._links.verify.href' `
        # echo -e "`date` 🅿 $OKTA_USER MFA PUSH LINK is: $MFA_PUSH_LINK"
        echo -e "`date` $OKTA_USER 🅿 MFA PUSH LINK sent"

        MFA_VERIFY=`curl -s -L -X POST -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: SSWS $OKTA_TOKEN" "$OKTA_HOST/api/v1/users/00uaymu8hgMU7E8hX4x6/factors/opfby5bhc004wyiPj4x6/verify"`
        MFA_CANCEL_LINK=`echo $MFA_VERIFY | jq -r '._links.cancel.href'`
        MFA_POLL_LINK=`echo $MFA_VERIFY | jq -r '._links.poll.href'`
        if [[ -n $MFA_POLL_LINK ]] ; then
            echo -e "`date` $OKTA_USER ⏳ MFA POLL LINK is: $MFA_POLL_LINK"
            for c in {1..7} ; do
                sleep 5
                FACTOR_RESULT=`curl -s -L -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: SSWS $OKTA_TOKEN" $MFA_POLL_LINK | jq -r '.factorResult'` 
                if [[ $FACTOR_RESULT == "SUCCESS" ]]; then
                    echo -e "`date` $OKTA_USER ✅ MFA PUSH APPROVED"
                    return 0 
                elif [[ $FACTOR_RESULT == "REJECTED" ]]; then
                    break 
                fi
            done
            echo -e "`date` $OKTA_USER ❌ MFA PUSH NOT APPROVED - $FACTOR_RESULT"
        fi

    else
        echo -e "`date` $OKTA_USER ⚠ couldn't get MFA PUSH ID \n$MFA_PUSH"
    fi
    curl -s -L -X DELETE -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: SSWS $OKTA_TOKEN" $MFA_CANCEL_LINK
    return 1 ;
}

##     ##    ###    #### ##    ##
###   ###   ## ##    ##  ###   ##
#### ####  ##   ##   ##  ####  ##
## ### ## ##     ##  ##  ## ## ##
##     ## #########  ##  ##  ####
##     ## ##     ##  ##  ##   ###
##     ## ##     ## #### ##    ##

#Okta login 
login $OKTA_USER $c2

#Check if openvpn app is assigned to the user
assignment_check "$APP_ID"

#GET MFA associated with the user
USERMFA=$(curl --fail -s --location -H 'Accept: application/json' -H 'Content-Type: application/json' -H "Authorization: SSWS $OKTA_TOKEN" "$OKTA_HOST/api/v1/users/$USER_ID/factors" || { echo -e "`date` $OKTA_USER ❌ couldn't get MFA details" && exit 1 ; }; )

#Send and confirm MFA Push
mfapush "$USERMFA"
PUSHRESULT="$?"

exit $PUSHRESULT



