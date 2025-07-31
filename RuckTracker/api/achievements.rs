use actix_web::{web, App, HttpServer, HttpResponse, Responder, Error as ActixError};
use actix_web::dev::ServiceRequest;
use actix_web::middleware::Logger;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use chrono::{DateTime, Utc, Duration, NaiveDate};
use log::{info, error, warn};
use uuid::Uuid;
use reqwest::Client; // For Supabase API calls (assuming no official Rust client, use HTTP)
use std::env;

// Assuming a simple in-memory cache for this example; use Redis in production
type Cache = Arc<Mutex<HashMap<String, (serde_json::Value, DateTime<Utc>)>>>;

// Supabase config
struct SupabaseConfig {
    url: String,
    anon_key: String,
    admin_key: String, // For admin operations
}

#[derive(Serialize, Deserialize, Clone)]
struct Achievement {
    id: i32,
    achievement_key: String,
    name: String,
    description: String,
    category: String,
    tier: String,
    criteria: HashMap<String, serde_json::Value>,
    icon_name: Option<String>,
    is_active: bool,
    created_at: Option<String>,
    updated_at: Option<String>,
    unit_preference: Option<String>,
}

#[derive(Serialize, Deserialize, Clone)]
struct UserAchievement {
    earned_at: String,
    metadata: HashMap<String, serde_json::Value>,
    user_id: Uuid,
    achievement: Achievement,
}

// Helper functions (deduplicated)

// Get Supabase client (HTTP)
async fn get_supabase_client(config: &SupabaseConfig, is_admin: bool) -> Client {
    let client = Client::new();
    client // In real, add auth headers with anon_key or admin_key
}

// Cache get (deduplicated)
async fn cache_get(cache: &Cache, key: &str) -> Option<serde_json::Value> {
    let cache = cache.lock().unwrap();
    if let Some((value, expiry)) = cache.get(key) {
        if Utc::now() < *expiry {
            return Some(value.clone());
        }
    }
    None
}

// Cache set (deduplicated)
fn cache_set(cache: &Cache, key: String, value: serde_json::Value, ttl_seconds: i64) {
    let mut cache = cache.lock().unwrap();
    cache.insert(key, (value, Utc::now() + Duration::seconds(ttl_seconds)));
}

// Execute Supabase query (deduplicated for all GET/POST)
async fn execute_supabase_query(
    config: &SupabaseConfig,
    table: &str,
    method: &str,
    params: Option<HashMap<String, serde_json::Value>>,
    is_admin: bool,
) -> Result<serde_json::Value, ActixError> {
    let client = get_supabase_client(config, is_admin).await;
    let url = format!("{}/rest/v1/{}", config.url, table);
    // Implement POST/GET with params, handle errors
    // For simplicity, assume GET
    let resp = client.get(&url).send().await.map_err(|e| {
        error!("Supabase query error: {}", e);
        ActixError::from(e)
    })?;
    resp.json().await.map_err(|e| {
        error!("JSON parse error: {}", e);
        ActixError::from(e)
    })
}

// Handlers

async fn achievements_handler(
    config: web::Data<SupabaseConfig>,
    cache: web::Data<Cache>,
    query: web::Query<HashMap<String, String>>,
) -> impl Responder {
    let unit_preference = query.get("unit_preference").cloned().unwrap_or("metric".to_string());
    let cache_key = format!("achievements:all:{}", unit_preference);

    if let Some(cached) = cache_get(&cache, &cache_key).await {
        return HttpResponse::Ok().json(json!({ "status": "success", "achievements": cached }));
    }

    match execute_supabase_query(&config, "achievements", "GET", None, false).await {
        Ok(data) => {
            // Filter by unit_preference (deduplicated logic)
            let filtered: Vec<Achievement> = data.as_array().unwrap().iter().filter_map(|item| {
                let ach: Achievement = serde_json::from_value(item.clone()).ok()?;
                if ach.unit_preference.is_none() || ach.unit_preference.as_ref() == Some(&unit_preference) {
                    Some(ach)
                } else {
                    None
                }
            }).collect();

            cache_set(&cache, cache_key, serde_json::to_value(&filtered).unwrap(), 1800);
            HttpResponse::Ok().json(json!({ "status": "success", "achievements": filtered }))
        }
        Err(e) => HttpResponse::InternalServerError().json(json!({ "error": "Failed to fetch achievements" })),
    }
}

// Similarly implement other handlers, deduplicating query execution, caching, filtering, etc.

// For CheckSessionAchievements - this is complex, deduplicate criteria checks into a function

async fn check_criteria(
    supabase: &Client, // Pass supabase client
    user_id: Uuid,
    session: &HashMap<String, serde_json::Value>,
    achievement: &Achievement,
    user_stats: &HashMap<String, f64>,
) -> bool {
    let criteria = &achievement.criteria;
    let criteria_type = criteria.get("type").and_then(|v| v.as_str()).unwrap_or("");

    match criteria_type {
        "first_ruck" => true,
        "single_session_distance" => {
            let target = criteria.get("target").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let distance = session.get("distance_km").and_then(|v| v.as_f64()).unwrap_or(0.0);
            distance >= target
        }
        // Deduplicate other criteria into match arms, reuse common logic like fetching stats
        _ => false,
    }
}

// In the handler, use this function for each achievement

// Server setup
#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();
    let config = SupabaseConfig {
        url: env::var("SUPABASE_URL").unwrap(),
        anon_key: env::var("SUPABASE_ANON_KEY").unwrap(),
        admin_key: env::var("SUPABASE_ADMIN_KEY").unwrap(),
    };
    let cache = web::Data::new(Arc::new(Mutex::new(HashMap::new())));

    HttpServer::new(move || {
        App::new()
            .wrap(Logger::default())
            .app_data(web::Data::new(config.clone()))
            .app_data(cache.clone())
            .route("/achievements", web::get().to(achievements_handler))
            // Add other routes similarly
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
} 