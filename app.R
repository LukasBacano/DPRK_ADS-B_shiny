library(shiny)
library(leaflet)
library(dplyr)
library(leaflet.extras)
library(rsconnect)


#brug CSV som data (dette er kun for display versionen, da den rigtige er live og kører SQL)
flights_data <- read.csv("dprk_Flights.csv", stringsAsFactors = FALSE)

ui <- fluidPage(
  titlePanel("DPRK Tracking"),
  tabsetPanel(
    # TAB 1: Fly-sporing
    tabPanel("Fly-sporing",
             sidebarLayout(
               sidebarPanel(
                 selectInput("country_select", "Vælg et land:", choices = "Alle"),
                 selectInput("icao", "Vælg et fly:", choices = NULL),
                 br(),
                 
                 uiOutput("time_slider_ui"),
                 br(),
                 actionButton("prev_time", "⬅️ Tidligere"),
                 actionButton("next_time", "Næste ➡️️"),
                 br(), br(),
                 
                 h4("Flyinformation"),
                 uiOutput("flightDetails")
               ),
               mainPanel(
                 leafletOutput("flightMap", height = "600px")
               )
             )
    ),
    
    # TAB 2: Heatmap
    tabPanel("Heatmap",
             leafletOutput("heatmap", height = "600px")
    ),
    
    # TAB 3: Alle positioner
    tabPanel("Alle positioner",
             leafletOutput("allFlightsMap", height = "600px")
    )
  )
)

server <- function(input, output, session) {
  
  #Bruges til at gemme tids-data for icao
  timeValues <- reactiveVal(NULL)
  
  #Loader lande
  observe({
    #kun unique og uden NA for origin_country
    lande <- unique(na.omit(flights_data$origin_country))
    
    updateSelectInput(session, "country_select",
                      choices = c("Alle", sort(lande)),
                      selected = "Alle"
    )
  })
  
  #Opdaterer icao-dropdown ud fra land valgt
  observeEvent(input$country_select, {
    req(input$country_select)
    
    if (input$country_select == "Alle") {
    
      flyList <- unique(flights_data$icao24)
    } else {
      # Filter by chosen country
      flyList <- unique(flights_data$icao24[
        flights_data$origin_country == input$country_select
      ])
    }
    
    if (length(flyList) == 0) {
      updateSelectInput(session, "icao", choices = "Ingen fly fundet")
    } else {
      updateSelectInput(session, "icao", choices = flyList)
    }
  })
  
  #bygger slideren 
  observeEvent(input$icao, {
    req(input$icao)
    
    #Filterer icao og sætter logtidspunkt i rækkefølge
    timeList <- flights_data$logged_at[flights_data$icao24 == input$icao]
    timeList <- sort(unique(timeList))  #rækkefølge + unique
    
    timeValues(timeList)
    
    if (length(timeList) > 0) {
      output$time_slider_ui <- renderUI({
        sliderInput(
          inputId = "time_slider_index",
          label = "Vælg observation:",
          min = 1,
          max = length(timeList),
          value = length(timeList),  # default to the most recent
          step = 1,
          animate = animationOptions(interval = 1000, loop = FALSE)
        )
      })
    } else {
      output$time_slider_ui <- renderUI({
        h4("Ingen data tilgængelig for dette fly.")
      })
    }
  })
  
  #hent data til slideren
  fetch_data <- reactive({
    req(input$icao, input$time_slider_index)
    
    allTimes <- timeValues()
    validate(
      need(length(allTimes) > 0, "Ingen tider"),
      need(input$time_slider_index <= length(allTimes), "Ugyldig indeks")
    )
    
    #Vælg tid ud fra log-tidspunkt
    chosenTime <- allTimes[input$time_slider_index]
    
    # filtrerer flydata ud fra icao og log-tidspunkt
    flyData <- flights_data[
      flights_data$icao24 == input$icao &
        flights_data$logged_at == chosenTime,
    ]
    
    #retunerer den række
    flyData
  })
  
#slider index til at vælge frame
  observeEvent(input$time_slider_index, {
    flyData <- fetch_data()
    validate(need(nrow(flyData) > 0, "Ingen data ved denne observation."))
    
    output$flightMap <- renderLeaflet({
      leaflet() %>%
        addTiles() %>%
        setView(lng = 127, lat = 40, zoom = 6) %>%
        addMarkers(
          lng = flyData$longitude, 
          lat = flyData$latitude,
          popup = paste(
            "Fly: ", flyData$icao24,
            "<br>Registreringsland: ", flyData$registration_country,
            "<br>Højde: ", round(flyData$geo_altitude, 1),
            "<br>Fart: ", round(flyData$velocity*3.6, 1), " km/t",
            "<br>Kurs: ", flyData$heading, "°",
            "<br>Tidspunkt: ", flyData$logged_at
          )
        )
    })
    
    #updater flydetaljer
    output$flightDetails <- renderUI({
      tagList(
        p(strong("Fly ICAO: "), flyData$icao24),
        p(strong("Fly ID: "), flyData$callsign),
        p(strong("Registreringsland: "), flyData$origin_country),
        p(strong("Tidspunkt: "), flyData$logged_at),
        p(strong("Højde: "), round(flyData$geo_altitude, 1), " meter"),
        p(strong("Fart: "), round(flyData$velocity*3.6, 1), " km/t"),
        p(strong("Breddegrader: "), flyData$latitude),
        p(strong("Længdegrader: "), flyData$longitude),
        p(strong("Transponderkode: "), flyData$squawk)
      )
    })
  })
  
 #knapper til at skifte "frame
  observeEvent(input$prev_time, {
    req(input$time_slider_index)
    current_idx <- input$time_slider_index
    new_idx <- max(1, current_idx - 1)
    updateSliderInput(session, "time_slider_index", value = new_idx)
  })
  
  observeEvent(input$next_time, {
    req(input$time_slider_index)
    current_idx <- input$time_slider_index
    new_idx <- min(length(timeValues()), current_idx + 1)
    updateSliderInput(session, "time_slider_index", value = new_idx)
  })
  
 #Heatmap
  all_flight_data <- reactive({
    flights_data %>%
      filter(latitude >= 35, latitude <= 45,
             longitude >= 120, longitude <= 135,
             !is.na(latitude), !is.na(longitude))
  })
  
  output$heatmap <- renderLeaflet({
    data <- all_flight_data()
    validate(need(nrow(data) > 0, "Ingen data til heatmap"))
    
    leaflet(data) %>%
      addProviderTiles(providers$OpenStreetMap) %>%
      addHeatmap(
        lng = ~longitude,
        lat = ~latitude,
        radius = 15,
        blur = 20,
        max = 0.01,
        group = "DPRK Heatmap"
      ) %>%
      setView(lng = 127, lat = 40, zoom = 6)
  })
  
#viser alle lokationer ud fra lat/long
  allPositionsData <- reactive({
    flights_data %>%
      filter(!is.na(latitude), !is.na(longitude)) %>%

      mutate(heading = true_track)
  })
  
  output$allFlightsMap <- renderLeaflet({
    data <- allPositionsData()
    validate(need(nrow(data) > 0, "Ingen positioner at vise."))
    
    leaflet(data) %>%
      addTiles() %>%
      addMarkers(
        lng = ~longitude,
        lat = ~latitude,
        popup = ~paste(
          "<b>ICAO:</b>", icao24,
          "<br><b>Callsign:</b>", callsign,
          "<br><b>Land:</b>", origin_country,
          "<br><b>Tid:</b>", logged_at,
          "<br><b>Højde:</b>", round(geo_altitude, 1), "m",
          "<br><b>Fart:</b>", round(velocity*3.6, 1), "km/t",
          "<br><b>Kurs:</b>", heading, "°"
        ),
        clusterOptions = markerClusterOptions()
      ) %>%
      setView(lng = 127, lat = 40, zoom = 6)
  })
}

shinyApp(ui, server)

