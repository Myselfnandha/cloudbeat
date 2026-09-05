use std::time::Duration;
use anyhow::{Context as _, Result};
use serde::{Deserialize, Serialize};

const SOURCE: &str = "NetEase";
const SEARCH_URL: &str = "https://music.163.com/api/search/get";
const LYRIC_URL: &str = "https://music.163.com/api/song/lyric/v1";
const USER_AGENT: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

#[derive(Debug, Serialize, Deserialize)]
pub struct NeteaseLyricsResponse {
    pub source: String,
    pub format: String, // "synced_yrc" | "synced_lrc" | "plain"
    pub title: String,
    pub artist: String,
    pub raw_lyrics: String,
    pub is_instrumental: bool,
    pub duration_ms: Option<u64>,
}

#[derive(Deserialize)]
struct SearchAnswer {
    result: Option<SearchResult>,
}

#[derive(Deserialize)]
struct SearchResult {
    #[serde(default)]
    songs: Vec<Song>,
}

#[derive(Deserialize, Clone)]
struct Song {
    id: u64,
    name: String,
    #[serde(default)]
    duration: u64,
    #[serde(default)]
    artists: Vec<Named>,
}

#[derive(Deserialize, Clone)]
struct Named {
    name: Option<String>,
}

#[derive(Deserialize)]
struct Sheet {
    lrc: Option<Verse>,
    yrc: Option<Verse>,
    #[serde(default, rename = "pureMusic")]
    pure_music: bool,
}

#[derive(Deserialize)]
struct Verse {
    lyric: Option<String>,
}

pub struct NetEaseClient {
    http: reqwest::Client,
}

impl NetEaseClient {
    pub fn new() -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(8))
                .build()
                .unwrap_or_default(),
        }
    }

    pub async fn fetch_lyrics(&self, title: &str, artist: &str, duration_ms: Option<u64>) -> Result<Option<NeteaseLyricsResponse>> {
        let wanted = format!("{} {}", title.trim(), artist.trim());
        let response = self
            .http
            .get(SEARCH_URL)
            .query(&[("s", wanted.as_str()), ("type", "1"), ("limit", "5")])
            .header("User-Agent", USER_AGENT)
            .header("Referer", "https://music.163.com")
            .send()
            .await
            .context("failed to reach netease search")?;

        if !response.status().is_success() {
            anyhow::bail!("netease search status {}", response.status());
        }

        let answer: SearchAnswer = response.json().await.context("failed to parse netease search response")?;
        let songs = answer.result.map(|r| r.songs).unwrap_or_default();
        if songs.is_empty() {
            return Ok(None);
        }

        // Pick closest duration or first song
        let song = if let Some(target_ms) = duration_ms {
            songs.iter().min_by_key(|s| {
                if s.duration > 0 {
                    (s.duration as i64 - target_ms as i64).abs()
                } else {
                    i64::MAX
                }
            }).cloned().unwrap_or_else(|| songs[0].clone())
        } else {
            songs[0].clone()
        };

        let lyric_resp = self
            .http
            .get(LYRIC_URL)
            .query(&[("id", song.id.to_string().as_str()), ("cp", "false")])
            .query(&[
                ("lv", "0"),
                ("tv", "0"),
                ("rv", "0"),
                ("kv", "0"),
                ("yv", "0"),
                ("ytv", "0"),
                ("yrv", "0"),
            ])
            .header("User-Agent", USER_AGENT)
            .header("Referer", "https://music.163.com")
            .send()
            .await
            .context("failed to reach netease lyric endpoint")?;

        if !lyric_resp.status().is_success() {
            anyhow::bail!("netease lyric status {}", lyric_resp.status());
        }

        let sheet: Sheet = lyric_resp.json().await.context("failed to parse netease lyric json")?;

        let is_instrumental = sheet.pure_music;
        let yrc_text = sheet.yrc.and_then(|v| v.lyric).filter(|t| !t.trim().is_empty());
        let lrc_text = sheet.lrc.and_then(|v| v.lyric).filter(|t| !t.trim().is_empty());

        let artists_str = song.artists.iter().filter_map(|a| a.name.clone()).collect::<Vec<_>>().join(", ");

        if let Some(yrc) = yrc_text {
            return Ok(Some(NeteaseLyricsResponse {
                source: SOURCE.to_string(),
                format: "synced_yrc".to_string(),
                title: song.name,
                artist: artists_str,
                raw_lyrics: yrc,
                is_instrumental,
                duration_ms: (song.duration > 0).then_some(song.duration),
            }));
        }

        if let Some(lrc) = lrc_text {
            let format = if lrc.contains('[') && lrc.contains(']') {
                "synced_lrc".to_string()
            } else {
                "plain".to_string()
            };

            return Ok(Some(NeteaseLyricsResponse {
                source: SOURCE.to_string(),
                format,
                title: song.name,
                artist: artists_str,
                raw_lyrics: lrc,
                is_instrumental,
                duration_ms: (song.duration > 0).then_some(song.duration),
            }));
        }

        if is_instrumental {
            return Ok(Some(NeteaseLyricsResponse {
                source: SOURCE.to_string(),
                format: "plain".to_string(),
                title: song.name,
                artist: artists_str,
                raw_lyrics: "[Instrumental]".to_string(),
                is_instrumental: true,
                duration_ms: (song.duration > 0).then_some(song.duration),
            }));
        }

        Ok(None)
    }
}
