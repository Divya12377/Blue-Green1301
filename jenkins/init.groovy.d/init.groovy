#!groovy

// Create admin user with desired username and password
def instance = jenkins.model.Jenkins.getInstance()
def hudsonRealm = new hudson.security.HudsonPrivateSecurityRealm(false)

// Change "yourusername" and "yourpassword" below to your desired credentials
def user = hudsonRealm.createAccount("admin", "123!@#")

instance.setSecurityRealm(hudsonRealm)

// Authorize full control to logged-in users
def strategy = new hudson.security.FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// Disable CSRF Protection (optional, but consider security implications)
instance.setCrumbIssuer(null)

instance.save()

