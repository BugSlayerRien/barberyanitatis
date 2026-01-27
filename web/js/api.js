// API Configuration
const API_BASE_URL = 'http://localhost:3000/api';

// Auth token management
function getAuthToken() {
    return localStorage.getItem('authToken');
}

function setAuthToken(token) {
    localStorage.setItem('authToken', token);
}

function clearAuthToken() {
    localStorage.removeItem('authToken');
}

// API Helper Function
async function apiCall(endpoint, options = {}) {
    const token = getAuthToken();
    const headers = {
        'Content-Type': 'application/json',
        ...options.headers
    };

    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }

    const response = await fetch(`${API_BASE_URL}${endpoint}`, {
        ...options,
        headers
    });

    if (response.status === 401) {
        // Unauthorized - redirect to login
        window.location.href = '/login.html';
        return;
    }

    return response.json();
}

// API Functions
const API = {
    // Authentication
    login: (email, password) => 
        apiCall('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ email, password })
        }),
    
    logout: () => apiCall('/auth/logout', { method: 'POST' }),
    
    // Appointments
    getAppointments: () => apiCall('/appointments'),
    getAppointment: (id) => apiCall(`/appointments/${id}`),
    createAppointment: (data) => 
        apiCall('/appointments', {
            method: 'POST',
            body: JSON.stringify(data)
        }),
    updateAppointment: (id, data) => 
        apiCall(`/appointments/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data)
        }),
    cancelAppointment: (id) => 
        apiCall(`/appointments/${id}`, { method: 'DELETE' }),
    
    // Stylists
    getStylists: () => apiCall('/stylists'),
    getStylist: (id) => apiCall(`/stylists/${id}`),
    getStylistAvailability: (id) => apiCall(`/stylists/${id}/availability`),
    
    // Services
    getServices: () => apiCall('/services'),
    getService: (id) => apiCall(`/services/${id}`),
    
    // Customers
    getCustomers: () => apiCall('/customers'),
    getCustomer: (id) => apiCall(`/customers/${id}`),
    
    // Analytics
    getDashboard: () => apiCall('/analytics/dashboard'),
    getRevenue: () => apiCall('/analytics/revenue'),
    getPopularServices: () => apiCall('/analytics/popular-services'),
    getStylistPerformance: () => apiCall('/analytics/stylist-performance'),
    
    // AI
    getAIRecommendations: (customerId) => 
        apiCall(`/ai/recommendations/${customerId}`),
    analyizeFace: (imageData) => 
        apiCall('/ai/analyze-face', {
            method: 'POST',
            body: JSON.stringify({ image: imageData })
        })
};
