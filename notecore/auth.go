package notecore

// AuthResult represents the result of a login attempt.
type AuthResult struct {
	Success bool   `json:"success"`
	Email   string `json:"email"`
	Message string `json:"message"`
}

// Login is a stub authentication function.
// It always succeeds regardless of input.
// This will be replaced with real JWT-based authentication in MVP-002.
func Login(email, password string) *AuthResult {
	if email == "" {
		return &AuthResult{
			Success: false,
			Message: "Email is required",
		}
	}
	if password == "" {
		return &AuthResult{
			Success: false,
			Message: "Password is required",
		}
	}
	return &AuthResult{
		Success: true,
		Email:   email,
		Message: "Login successful",
	}
}
