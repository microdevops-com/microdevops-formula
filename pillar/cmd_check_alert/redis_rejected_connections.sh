#!/bin/bash

###########################################################
#                                                         #
# If simple password authentication is enabled in Redis,  # 
# create a /root/.redis file with the "AUTH" variable     #
# that contains the password for Redis authorization.     #
# Example: AUTH=My-Super-Strong-Password-777              #
#                                                         #
###########################################################

if [[ -f /root/.redis ]]; then
  source /root/.redis
  if [[ $(redis-cli -a ${AUTH} --no-auth-warning PING 2>/dev/null) == "PONG" ]]; then 
    if [[ $(redis-cli -a ${AUTH} --no-auth-warning INFO | grep rejected_connections | sed "s/rejected_connections://") == 0 ]]; then 
      true;
    else  
      false; 
    fi;  
  else
    false; 
  fi;
else
  if [[ $(redis-cli PING 2>/dev/null) == "PONG" ]]; then 
    if [[ $(redis-cli INFO | grep rejected_connections | sed "s/rejected_connections://") == 0 ]]; then 
      true; 
    else  
      false; 
    fi;  
  else
    false; 
  fi;
fi
