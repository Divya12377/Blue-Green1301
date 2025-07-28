#!/bin/bash
CURRENT_COLOR=$(kubectl get svc nodejs-app-service -o=jsonpath='{.spec.selector.version}')

if [ "$CURRENT_COLOR" = "blue" ]; then
  NEW_COLOR="green"
else
  NEW_COLOR="blue"
fi

kubectl patch svc nodejs-app-service -p "{\"spec\":{\"selector\":{\"version\":\"$NEW_COLOR\"}}}"
echo "Switched traffic to $NEW_COLOR deployment"

# Wait for service to stabilize
sleep 10

# Verify switch
echo "Current active version: $(kubectl get svc nodejs-app-service -o=jsonpath='{.spec.selector.version}')"
