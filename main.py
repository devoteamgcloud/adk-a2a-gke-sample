import os
import datetime
from zoneinfo import ZoneInfo
from google.adk.agents.llm_agent import Agent
from google.adk.a2a.utils.agent_to_a2a import to_a2a

def get_weather(city: str) -> dict:
    """Retrieves the current weather report for a specified city.

    Args:
        city (str): The name of the city for which to retrieve the weather report.

    Returns:
        dict: status and result or error msg.
    """
    weather_data = {
        "new york": {"temperature": "25", "unit": "Celsius", "conditions": "sunny"},
        "london": {"temperature": "18", "unit": "Celsius", "conditions": "cloudy"},
        "tokyo": {"temperature": "28", "unit": "Celsius", "conditions": "humid"},
        "paris": {"temperature": "22", "unit": "Celsius", "conditions": "partly cloudy"},
        "sydney": {"temperature": "30", "unit": "Celsius", "conditions": "hot and clear"},
    }
    city_lower = city.lower()
    if city_lower in weather_data:
        data = weather_data[city_lower]
        report = (
            f"The weather in {city} is {data['conditions']} with a temperature of "
            f"{data['temperature']} degrees {data['unit']}."
        )
        return {"status": "success", "report": report}
    else:
        return {
            "status": "error",
            "error_message": f"Weather information for '{city}' is not available.",
        }

def get_current_time(city: str) -> dict:
    """Returns the current time in a specified city.

    Args:
        city (str): The name of the city for which to retrieve the current time.

    Returns:
        dict: status and result or error msg.
    """
    timezone_map = {
        "new york": "America/New_York",
        "london": "Europe/London",
        "tokyo": "Asia/Tokyo",
        "paris": "Europe/Paris",
        "sydney": "Australia/Sydney",
    }
    city_lower = city.lower()
    if city_lower in timezone_map:
        tz_identifier = timezone_map[city_lower]
    else:
        return {
            "status": "error",
            "error_message": (f"Sorry, I don't have timezone information for {city}."),
        }

    tz = ZoneInfo(tz_identifier)
    now = datetime.datetime.now(tz)
    report = f"The current time in {city} is {now.strftime('%Y-%m-%d %H:%M:%S %Z%z')}"
    return {"status": "success", "report": report}

sample_agent = Agent(
    model="gemini-2.5-flash",
    name="sample_agent",
    description=("Agent to answer questions about the time and weather in a city."),
    instruction=(
        "You are a helpful agent who can answer user questions about the time and weather in a city."
    ),
    tools=[get_weather, get_current_time],
)

app = to_a2a(
    sample_agent,
    host=os.environ.get("A2A_HOST", "localhost"),
    port=int(os.environ.get("A2A_PORT", 443)),
    protocol=os.environ.get("A2A_PROTOCOL", "https"),
)